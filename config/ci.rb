# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "env CI=true PARALLEL_WORKERS=1 bin/rails db:test:prepare test"
  step "Tests: JavaScript", "node --test test/javascript/*.mjs"
  step "Tests: Browser", "env CI=true PARALLEL_WORKERS=1 bin/rails test:system"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
  step "Production: Docker build and boot", "bash bin/check-production-image"
end
