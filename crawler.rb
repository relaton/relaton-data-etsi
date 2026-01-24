# frozen_string_literal: true

require "fileutils"

require "relaton/etsi/data_fetcher"

FileUtils.rm_rf "data"
FileUtils.rm Dir.glob("index*")

Relaton::Etsi::DataFetcher.fetch
