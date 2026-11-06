# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "pagedjs", to: "paged.esm.js", preload: false # @0.4.3
pin "pdfjs-dist", to: "pdfjs.js", preload: false # @6.5.438
pin "e_invoice", to: "e_invoice.js", preload: false
pin_all_from "app/javascript/controllers", under: "controllers"
pin "expense_search", to: "expense_search.js"
pin "price_input", to: "price_input.js"
pin "trix", to: "trix.js"
pin "@rails/actiontext", to: "actiontext.esm.js"
