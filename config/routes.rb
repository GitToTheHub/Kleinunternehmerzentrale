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
  resource :workflow, path: "einstellungen", only: %i[edit update]
  get "gruendungskosten", to: "pages#gruendungskosten"
  get "gewerbeanmeldung", to: "pages#gewerbeanmeldung"
  get "vorteile", to: "pages#vorteile"
  get "datenschutz", to: "pages#datenschutz"
  get "hilfe", to: "pages#hilfe"
  get "spenden", to: "pages#spenden"
  get "e-rechnungsviewer", to: "pages#e_invoice_viewer", as: :e_invoice_viewer
  patch "start_steps/:key", to: "start_steps#update", as: :start_step
  get "buchhaltung/jahresabschluss", to: "bookkeeping_entries#annual", as: :annual_bookkeeping
  get "buchhaltung/geraete", to: redirect("/anlagegueter/new")
  resources :bookkeeping_entries, path: "buchhaltung", except: :show do
    collection do
      get "euer-vorbereiten", action: :prepare_euer, as: :prepare_euer
    end
    member do
      get :refund
      post :create_refund
    end
  end
  resources :business_assets, path: "anlagegueter", except: :show
  resource :euer_statement, path: "euer", only: %i[edit update]
  resource :euer_expense_policy, path: "euer-ausgabenmethode", only: %i[edit update]
  resources :euer_adjustments, path: "euer-ergaenzungen", except: %i[index show]
  resources :bookkeeping_imports, path: "buchhaltung-uebernehmen", only: %i[new create show destroy] do
    collection do
      post :preview
      get :template
    end
  end
  resource :export, only: :show
  resource :account, only: %i[new create destroy]
  resource :session, only: %i[new create destroy]
  resource :confirmation, only: :create
  get "confirmations/:token", to: "confirmations#show", as: :confirm_email
  resources :password_resets, only: %i[new create edit update], param: :token
  resources :sales_documents, path: "angebote-und-auftraege", except: :destroy do
    get :next_number, path: "naechste-nummer", on: :collection
    post :accept, path: "als-auftrag-uebernehmen", on: :member
  end
  resources :invoices, path: "rechnungen", path_names: { new: "neu" }, only: %i[index new create show] do
    get :xrechnung, on: :member
    post :cancel, path: "stornieren", on: :member
    post :preview, path: "vorschau", on: :collection
    get :exchange_rate, path: "wechselkurs", on: :collection
    get :next_number, path: "naechste-nummer", on: :collection
    get "entwuerfe/:draft_id/vorschau", on: :collection, action: :draft_preview, as: :draft_preview
    get "entwuerfe/:draft_id/bearbeiten", on: :collection, action: :new, as: :edit_draft
    patch "entwuerfe/:draft_id", on: :collection, action: :save_draft, as: :save_invoice_draft
    delete "entwuerfe/:draft_id", on: :collection, action: :discard_draft, as: :discard_invoice_draft
    post :lookup_customer_imprint, path: "kundenimpressum-suchen", on: :collection
    get :preview, path: "vorschau", on: :collection, to: redirect("/rechnungen/neu")
    patch :draft, path: "entwurf", on: :collection, action: :save_draft
    delete :draft, path: "entwurf", on: :collection, action: :discard_draft
  end

  # Keep previously shared invoice links usable.
  {
    "invoices" => "rechnungen",
    "invoices/new" => "rechnungen/neu",
    "invoices/preview" => "rechnungen/neu",
    "invoices/next_number" => "rechnungen/naechste-nummer",
    "invoices/drafts/:draft_id/edit" => "rechnungen/entwuerfe/%{draft_id}/bearbeiten",
    "invoices/drafts/:draft_id/preview" => "rechnungen/entwuerfe/%{draft_id}/vorschau",
    "invoices/:id/xrechnung" => "rechnungen/%{id}/xrechnung",
    "invoices/:id" => "rechnungen/%{id}"
  }.each do |old_path, new_path|
    get old_path, to: redirect("/#{new_path}")
  end
end
