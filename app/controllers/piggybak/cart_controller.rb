module Piggybak
  class CartController < Microsite::ApplicationController
    def show
      @cart = Cart.new(cookies["cart"])
      @cart.update_quantities
      cookies["cart"] = { :value => @cart.to_cookie, :path => '/' }
    end
  
    def add
      cookies["cart"] = { :value => Cart.add(cookies["cart"], params), :path => '/' }
      redirect_to piggybak.cart_url
    end
    
    def add_ajax
      cookies["cart"] = { :value => Cart.add(cookies["cart"], params), :path => '/' }
      @cart = Cart.new(cookies["cart"])
      @cart.update_quantities      
      render plain: @cart.items_total
#      sellable = params[:sellable_id]
      
      #fadein_text = "<div class=\"product_added_box\"><h5><i class=\"fa fa-check\"></i>Gram Û20 added</h5><div class=\"product_added_cart\"><i class=\"fa fa-shopping-cart\"></i></div></div>"                                  
                
    end    
  
    def remove
      response.set_cookie("cart", { :value => Cart.remove(cookies["cart"], params[:item]), :path => '/' })
      redirect_to piggybak.cart_url
    end
  
    def clear
      cookies["cart"] = { :value => '', :path => '/' }
      redirect_to piggybak.cart_url
    end
  
    def update
      cookies["cart"] = { :value => Cart.update(cookies["cart"], params), :path => '/' }
      redirect_to piggybak.cart_url
    end
  end
end
