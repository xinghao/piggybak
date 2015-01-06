module Piggybak
  class AdminMailer < InternalMailer
    ADMIN_MAIL = "admin@airarena.net"
    CC_MAIL = "jeremy.guth@airarena.net"
    def order_notification(order)
      @order = order
      @dispensary = order.dispensary
      dispensary_name = ""
      dispensary_name = @dispensary.name if !@dispensary.nil?
      mail(:to => ADMIN_MAIL, :cc => CC_MAIL,
           :subject => "Order ##{@order.number} has been placed to #{dispensary_name}")
    end
    
  end    
end
