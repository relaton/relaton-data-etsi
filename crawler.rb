# frozen_string_literal: true

require "relaton_etsi"

FileUtils.rm_rf "data"
FileUtils.rm Dir.glob("index*")

RelatonEtsi::DataFetcher.fetch
