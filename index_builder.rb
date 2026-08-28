# frozen_string_literal: true

require "date"
require "yaml"

# Builds the legacy `index-v1.yaml` this repository publishes.
#
# `Relaton::Etsi::DataFetcher` writes only the pubid-structured `index-v2.yaml`
# (`relaton/lib/relaton/etsi.rb`, `INDEXFILE = "index-v2"`). The released
# `relaton-etsi` 2.1.x still downloads `index-v1.zip` from this branch, so the
# crawler keeps producing it here. relaton-data-iana, relaton-data-ccsds and
# relaton-data-bipm carry the same arrangement.
#
# Without this, `index-v1.yaml` is simply never rewritten: crawler.rb deletes it
# on disk, but relaton/support's shared crawler.yml stages the indexes with the
# shell glob `git add index*.yaml`, which matches only files that still exist,
# so the deletion is never committed and the old blob stays frozen at HEAD. That
# is what metanorma/metanorma-pdfa#95 reports -- a row naming a data file the
# crawl had since deleted, which the client resolves to a 404 and reports as
# "Not found".
#
# The rows come from the `data/` tree and from nothing else. Each row's id is
# the document's primary docidentifier, which is the string
# `Relaton::Etsi::DataFetcher#save` indexes on and therefore the string the
# client searches for. Only that one field is read -- no bibitem
# deserialization -- so data-model drift in the relaton gem cannot break the
# rebuild. Unlike the ccsds and iso builders, no pubid is needed at all: an ETSI
# v1 id is the docidentifier verbatim, so this runs in the crawler's own process
# instead of a child with a legacy bundle.
#
# It does not read `index-v2.yaml`, and cannot usefully cross-check against it:
# `Relaton::Etsi::DataFetcher#save` writes the data file and adds the v2 index
# row in one method, returning before either when pubid rejects the id, so the
# two always agree by construction. A truncated crawl leaves them short
# together, which no comparison between them can see.
module EtsiIndexBuilder
  Error = Class.new(StandardError)

  DATA_GLOB = "data/*.yaml"
  INDEX_V1 = "index-v1.yaml"

  module_function

  # The index-v1 rows: `{ id: <primary docidentifier>, file: <path> }` in sorted
  # glob order.
  #
  # Raises when any data file yields no id. Every document in `data/` must reach
  # the index: dropping one silently is the divergence that produced
  # metanorma/metanorma-pdfa#95, and a red crawl is cheaper to notice than an
  # index that is quietly one record short.
  def rows(glob: DATA_GLOB)
    found = primary_docids(glob: glob)
    check_complete! found
    found.map { |file, id| { id: id, file: file } }
  end

  # Rebuild INDEX_V1 from the data/ tree. Writes nothing if a document cannot be
  # indexed, so a short walk cannot publish a truncated index.
  def build_index_v1(file: INDEX_V1, glob: DATA_GLOB)
    data_rows = rows(glob: glob)

    File.write file, data_rows.to_yaml
    puts "index-v1: wrote #{data_rows.size} entries to #{file}"
    data_rows
  end

  # -- internals ------------------------------------------------------------

  # `{ file => id }` for every data file, in sorted glob order, with the id left
  # nil where it could not be read. One unreadable document must not abort the
  # walk before the others are reported, so the failure is collected here and
  # raised once in .check_complete!.
  def primary_docids(glob: DATA_GLOB)
    Dir[glob].sort.to_h do |file|
      [file, begin
        primary_docid(file)
      rescue StandardError => e
        warn "index-v1: cannot read the docidentifier of #{file}: #{e.class}: #{e.message}"
        nil
      end]
    end
  end

  # The content of the document's primary docidentifier.
  #
  # `Relaton::Etsi::DataFetcher#save` indexes `bib.docidentifier.first.content`,
  # and every record in the corpus carries exactly one docidentifier, marked
  # primary. Keying on `primary` rather than on position means a record that
  # ever carries a second identifier -- a 3GPP number on a transposed TS, say --
  # still indexes under the one the client searches for.
  #
  # Date and Time are permitted because Psych instantiates them: ETSI writes
  # `at: 2004-06`, which stays a String, but one record with a full `2004-06-15`
  # would otherwise raise Psych::DisallowedClass and fail the whole rebuild.
  def primary_docid(file)
    doc = YAML.safe_load_file(file, permitted_classes: [Date, Time])
    return nil unless doc.is_a? Hash

    primary = Array(doc["docidentifier"]).find { |d| d.is_a?(Hash) && d["primary"] }
    primary && primary["content"]
  end

  def check_complete!(found)
    lost = found.select { |_file, id| id.to_s.empty? }.keys
    return if lost.empty?

    raise Error, "index-v1: #{lost.size} document(s) in #{DATA_GLOB} yielded no " \
                 "primary docidentifier, so the index would publish short of " \
                 "the corpus:\n#{lost.first(20).map { |f| "  #{f}" }.join("\n")}"
  end
end
