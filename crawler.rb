# frozen_string_literal: true

require "fileutils"

require "relaton/etsi/data_fetcher"
require_relative "index_builder"

FileUtils.rm_rf "data"
# Match only the generated `index-*` outputs (index-v1.yaml, index-v2.yaml and
# their zips) -- NOT the `index_builder.rb` source this crawler requires, which a
# bare `index*` glob would delete out from under the next run.
# spec/crawler_sources_spec.rb guards this.
FileUtils.rm Dir.glob("index-*")

# Writes index-v2.yaml only.
Relaton::Etsi::DataFetcher.fetch

# index-v1 (the legacy string-keyed index): rebuilt here over the data/ tree,
# because the released relaton-etsi still reads index-v1.zip from this branch.
# Same arrangement as relaton-data-iana and relaton-data-ccsds.
#
# Zipping and committing are not done here -- relaton/support's shared
# crawler.yml zips every index*.yaml and commits both the yaml and the zip.
EtsiIndexBuilder.build_index_v1
