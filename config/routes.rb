Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  root "home#index"
  get "/book", to: "guest_bookings#index", as: :guest_booking
  get "/book/details", to: "guest_bookings#new", as: :new_guest_booking
  get "/book/review", to: "guest_bookings#review", as: :guest_booking_review
  post "/book/checkout", to: "guest_bookings#checkout", as: :guest_booking_checkout
  post "/book/emergency-unpaid", to: "guest_bookings#emergency_unpaid", as: :guest_booking_emergency_unpaid
  get "/book/emergency-confirmation", to: "guest_bookings#emergency_confirmation", as: :guest_booking_emergency_confirmation
  get "/book/payments/:id", to: "guest_bookings#payment_status", as: :guest_booking_payment
  post "/book/details", to: "guest_bookings#create", as: :guest_booking_details

  devise_for :users, controllers: { sessions: "users/sessions" }

  devise_for :patient_accounts,
    path: "patients",
    path_names: { sign_in: "sign_in", sign_out: "sign_out", sign_up: "sign_up" },
    controllers: {
      registrations: "patient_accounts/registrations",
      sessions: "patient_accounts/sessions",
      confirmations: "patient_accounts/confirmations"
    }

  get "/patient-portal", to: "patient_portal/dashboard#show", as: :patient_portal
  get "/patient-portal/appointments", to: "patient_portal/appointments#index", as: :patient_portal_appointments
  get "/patient-portal/payments/:id", to: "patient_portal/appointment_payments#show", as: :patient_portal_payment
  get "/patient-portal/appointment-holds/:appointment_hold_id/payment", to: "patient_portal/appointment_payments#checkout"
  post "/patient-portal/appointment-holds/:appointment_hold_id/payment", to: "patient_portal/appointment_payments#create", as: :patient_portal_appointment_hold_payment
  post "/patient-portal/appointment-holds/:appointment_hold_id/emergency-unpaid", to: "patient_portal/emergency_bookings#create", as: :patient_portal_emergency_unpaid_booking
  get "/patient-portal/emergency-bookings/:id", to: "patient_portal/emergency_bookings#show", as: :patient_portal_emergency_booking
  resources :patient_portal_appointment_holds, path: "/patient-portal/appointment-holds", module: :patient_portal, controller: :appointment_holds, only: %i[create show]

  get "/staff/invitation/accept", to: "staff/invitations#edit", as: :edit_staff_invitation
  patch "/staff/invitation/accept", to: "staff/invitations#update", as: :staff_invitation

  get "/docs/user_manual", to: "staff/documentation#user_manual", as: :user_manual
  get "/docs/images/user_manual/:image", to: "staff/documentation#image",
      as: :user_manual_image, format: false,
      constraints: { image: /[a-z0-9-]+\.png/ }

  # Reveal health status on /up that returns 200 if the app boots
  # with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/practice", module: "staff", as: "practice" do
  resource :stripe_outage, only: %i[show create], controller: "stripe_outages"
  resource :consultation_fees, only: %i[edit update], controller: "consultation_fees"
  resources :refunds, only: %i[index]
  resources :patients, only: %i[index show new create edit update]
  resources :patient_account_requests, only: %i[index show] do
    member do
      post :verify
      post :approve
      patch :revoke
      patch :reinstate
    end
  end
  resources :staff_members, only: %i[index new create edit update] do
    member do
      patch :access_level
      patch :deactivate
      patch :reactivate
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
    get :search_patients
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
