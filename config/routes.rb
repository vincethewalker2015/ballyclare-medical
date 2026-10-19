Rails.application.routes.draw do
  root "home#index"

  devise_for :users

  get "/docs/user_manual", to: "staff/documentation#user_manual", as: :user_manual
  get "/docs/images/user_manual/:image", to: "staff/documentation#image",
      as: :user_manual_image, format: false,
      constraints: { image: /[a-z0-9-]+\.png/ }

  # Reveal health status on /up that returns 200 if the app boots
  # with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/practice", module: "staff", as: "practice" do
  resources :patients, only: %i[index show new create edit update]
  resources :staff_members, only: %i[index new create] do
    member do
      patch :access_level
    end
  end
  resources :availability_blocks,
        path: "availability",
        only:  %i[index new create edit update] do
          member do
            patch :cancel
          end
        end
  resources :appointments, only: %i[index show new create] do
  collection do
    get :available_slots
  end

  member do
    patch :status
  end

  resource :charge,
         only: %i[new create],
         controller: "appointment_charges"

  resource :payment,
           only: %i[new create],
           controller: "appointment_payments" do
    get :status
  end
end
end

  post "/webhooks/stripe",
       to: "webhooks/stripe#create",
       as: :stripe_webhook
end
