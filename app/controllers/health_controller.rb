class HealthController < ActionController::API
  def show
    render json: "API is listening"
  end
end