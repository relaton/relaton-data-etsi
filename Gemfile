# frozen_string_literal: true

source "https://rubygems.org"

gem "relaton", git: "https://github.com/relaton/relaton.git", branch: "main"
gem "pubid", git: "https://github.com/metanorma/pubid.git", branch: "main"

# yeptris 0.6.28.4 and 0.6.28.5 leak ~100 KB of native memory on every YAML
# dump/load (leptris/yeptris-ruby#259, fixed in 0.6.28.6); the crawl serializes
# ~67k records and a leaking version runs the GitHub runner out of memory.
gem "yeptris", ">= 0.6.28.6"

group :test do
  gem "rspec", "~> 3.13"
end
