module Piggybak
  class OrdersController < Microsite::ApplicationController  
   
  before_filter :auth_user
  #before_filter :load_shipment_methods
    
  def auth_user    
    if !user_signed_in?
      session[:previous_url] = request.fullpath
      redirect_to microsite.new_user_session_url      
    end
  end

  # def load_shipment_methods
    # @delivery = Piggybak::ShippingMethod.get_delivery_method
    # @pickup = Piggybak::ShippingMethod.get_pickup_method
  # end
  
  def show
    @order = Piggybak::Order.find_by(number: params[:id])
    if @order.nil?
      render :file => "#{Rails.root}/public/404.html",  :status => 404
      return
    end
    
  end
    
    def submit
      
      response.headers['Cache-Control'] = 'no-cache'
      
      @cart = Piggybak::Cart.new(request.cookies["cart"])
      
      if request.post?
        logger = Logger.new("#{Rails.root}/#{Piggybak.config.logging_file}") 
        begin
          ActiveRecord::Base.transaction do
            
            @order = Piggybak::Order.new(orders_params)
            
            @order.dispensary_id = @microsite.dispensary_id
            @order.microsite_order = true
            @order.admin_created_order = false
            @order.create_payment_shipment
            
            
            if Piggybak.config.logging
              clean_params = params[:order].clone
              clean_params[:line_items_attributes].each do |k, li_attr|
                if li_attr[:line_item_type] == "payment" && li_attr.has_key?(:payment_attributes)
                  if li_attr[:payment_attributes].has_key?(:number)
                    li_attr[:payment_attributes][:number] = li_attr[:payment_attributes][:number].mask_cc_number
                  end
                  if li_attr[:payment_attributes].has_key?(:verification_value)
                    li_attr[:payment_attributes][:verification_value] = li_attr[:payment_attributes][:verification_value].mask_csv
                  end
                end
              end
              logger.info "#{request.remote_ip}:#{Time.now.strftime("%Y-%m-%d %H:%M")} Order received with params #{clean_params.inspect}" 
            end
            
            @order.initialize_user(current_user)
            @order.ip_address = request.remote_ip 
            @order.user_agent = request.user_agent
              
            @order.add_line_items(@cart)
            
            if Piggybak.config.logging
              logger.info "#{request.remote_ip}:#{Time.now.strftime("%Y-%m-%d %H:%M")} Order contains: #{cookies["cart"]} for user #{current_user ? current_user.email : 'guest'}"
            end
            
            if @order.is_pickup_order?
              @order.shipping_address = nil
              @order.no_phone
            end  
            
            Rails.logger.info @order.to_json
            Rails.logger.info @order.line_items.to_json
            
            if @order.save
            
              if Piggybak.config.logging
                logger.info "#{request.remote_ip}:#{Time.now.strftime("%Y-%m-%d %H:%M")} Order saved: #{@order.inspect}"
              end
              
              cookies["cart"] = { :value => '', :path => '/' }
              session[:last_order] = @order.id
              redirect_to piggybak.receipt_url 
            else
            
              if Piggybak.config.logging
                logger.info.warn "#{request.remote_ip}:#{Time.now.strftime("%Y-%m-%d %H:%M")} Order failed to save #{@order.errors.full_messages} with #{@order.inspect}."
              end
              raise Exception, @order.errors.full_messages
            end
            
          end
        rescue Exception => e
          Rails.logger.info "#{e.inspect}"
          if Piggybak.config.logging
            logger.warn "#{request.remote_ip}:#{Time.now.strftime("%Y-%m-%d %H:%M")} Order exception: #{e.inspect}"
          end
          if @order.errors.empty?
            @order.errors[:base] << "Your order could not go through. Please try again."
          end
        end
      else
        @order = Piggybak::Order.new
        @order.create_payment_shipment
        @order.initialize_user(current_user)
        @order.autofill_shopping_address
      end
    end
  
    def receipt
      response.headers['Cache-Control'] = 'no-cache'

      if !session.has_key?(:last_order)
        redirect_to main_app.root_url 
        return
      end

      @order = Piggybak::Order.where(id: session[:last_order]).first
    end

    def list
      redirect_to main_app.root_url if current_user.nil?
    end

    def download
      @order = Piggybak::Order.where(id: params[:id]).first

      if can?(:download, @order)
        render :layout => false
      else
        render "no_access"
      end
    end

    def email
      order = Piggybak::Order.where(id: params[:id]).first

      if can?(:email, order)
        Piggybak::Notifier.order_notification(order).deliver
        flash[:notice] = "Email notification sent."
        OrderNote.create(:order_id => order.id, :note => "Email confirmation manually sent.", :user_id => current_user.id)
      end

      redirect_to rails_admin.edit_path('Piggybak::Order', order.id)
    end

    def cancel
      order = Piggybak::Order.where(number: params[:id]).first

      if current_user.dispensary_owner?(@microsite.dispensary)   #can?(:cancel, order)
        order.recorded_changer = current_user.id
        order.disable_order_notes = true

        order.line_items.each do |line_item|
          if line_item.line_item_type != "payment"
            #line_item.mark_for_destruction
          end
        end

        if order.is_pickup_order?
          order.shipping_address = nil
        end 

        

        order.update_attribute(:total, 0.00)
                    

        order.update_attribute(:to_be_cancelled, true)

        OrderNote.create(:order_id => order.id, :note => "Order set to cancelled. Line items, shipments, tax removed.", :user_id => current_user.id)

        flash[:notice] = "Order #{order.id} set to cancelled. Order is now in unbalanced state."
      else
        flash[:error] = "You do not have permission to cancel this order."
      end

      redirect_to microsite.backend_orders_path #rails_admin.edit_path('Piggybak::Order', order.id)
    end

    # AJAX Actions from checkout
    def shipping
      cart = Piggybak::Cart.new(request.cookies["cart"])
      cart.set_extra_data(params)
      shipping_methods = Piggybak::ShippingMethod.lookup_methods(cart)
      render :json => shipping_methods
    end

    def tax
      cart = Piggybak::Cart.new(request.cookies["cart"])
      cart.set_extra_data(params)
      total_tax = Piggybak::TaxMethod.calculate_tax(cart)
      render :json => { :tax => total_tax }
    end

    def geodata
      countries = ::Piggybak::Country.all.includes(:states)
      data = countries.inject({}) do |h, country|
        h["country_#{country.id}"] = country.states
        h
      end
      render :json => { :countries => data }
    end

    private
    def orders_params
      nested_attributes = [shipment_attributes: [:shipping_method_id], 
                           payment_attributes: [:number, :verification_value, :month, :year, :payment_method_id]].first.merge(Piggybak.config.additional_line_item_attributes)
      line_item_attributes = [:sellable_id, :price, :unit_price, :description, :quantity, :line_item_type, nested_attributes]
      params.require(:order).permit(:user_id, :email, :phone, :ip_address,
                                    billing_address_attributes: [:firstname, :lastname, :address1, :location, :address2, :city, :state_id, :zip, :country_id],
                                    shipping_address_attributes: [:firstname, :lastname, :address1, :location, :address2, :city, :state_id, :zip, :country_id, :copy_from_billing],
                                    line_items_attributes: line_item_attributes)

    end
  end
end
