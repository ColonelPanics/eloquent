# Pin npm packages by running ./bin/importmap

pin 'application', preload: true
pin '@hotwired/turbo-rails', to: 'turbo.min.js', preload: true
pin '@hotwired/stimulus', to: 'stimulus.min.js', preload: true
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js', preload: true
pin_all_from 'app/javascript/controllers', under: 'controllers'

# Charting library
pin 'chartkick', to: 'chartkick.js'
pin 'Chart.bundle', to: 'Chart.bundle.js'
pin 'el-transition', to: 'https://ga.jspm.io/npm:el-transition@0.0.7/index.js'
pin "@wizardhealth/stimulus-multiselect", to: "https://ga.jspm.io/npm:@wizardhealth/stimulus-multiselect@1.0.0/src/multiselect.js"
