Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "pages#home"
  get "gruendungskosten", to: "pages#gruendungskosten"
  get "gewerbeanmeldung", to: "pages#gewerbeanmeldung"
  get "vorteile", to: "pages#vorteile"
  get "datenschutz", to: "pages#datenschutz"
  get "spenden", to: "pages#spenden"
  patch "start_steps/:key", to: "start_steps#update", as: :start_step
  resource :export, only: :show
  resource :account, only: %i[new create destroy]
  resource :session, only: %i[new create destroy]
  resources :invoices, only: %i[index new create show] do
    get :xrechnung, on: :member
    post :cancel, on: :member
    post :preview, on: :collection
    get :preview, on: :collection, to: redirect("/invoices/new")
  end
end
