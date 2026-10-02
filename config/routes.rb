Rails.application.routes.draw do
  devise_for :users

  # Reveal health status on /up that returns 200 if the app boots
  # with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/practice",
        module: "staff",
        as: "practice" do
    resources :appointments, only: %i[index show new create]
  end

  post "/webhooks/stripe",
       to: "webhooks/stripe#create",
       as: :stripe_webhook

  # root "posts#index"
end
