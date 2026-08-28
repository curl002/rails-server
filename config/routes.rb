Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Rails' built-in health check
  get "up" => "rails/health#show", as: :rails_health_check

  # API landing response
  root "health#show"

  # Defines the root path route ("/")
  # root "posts#index"
end
