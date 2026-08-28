# frozen_string_literal: true

RSpec.describe EtsiIndexBuilder do
  # The record the issue asks about, and the edition that superseded it.
  # `let`, not constants: a constant assigned inside a `describe` block lands on
  # Object, not on the example group, and leaks into every other spec file.
  let(:v121) { "data/etsi-en-319-142-1-v1-2-1-2024-01.yaml" }
  let(:v130) { "data/etsi-en-319-142-1-v1-3-0-2026-08.yaml" }
  let(:id121) { "ETSI EN 319 142-1 V1.2.1 (2024-01)" }
  let(:id130) { "ETSI EN 319 142-1 V1.3.0 (2026-08)" }

  describe ".rows" do
    it "reads the primary docidentifier of every data file, in sorted glob order" do
      in_workdir("data/b.yaml" => doc("ETSI EN 300 175-1 V2.5.1 (2013-08)"),
                 "data/a.yaml" => doc("ETSI EG 200 053 V1.5.1 (2004-06)")) do
        expect(described_class.rows).to eq(
          [{ id: "ETSI EG 200 053 V1.5.1 (2004-06)", file: "data/a.yaml" },
           { id: "ETSI EN 300 175-1 V2.5.1 (2013-08)", file: "data/b.yaml" }],
        )
      end
    end

    # `docidentifier.first` is what Relaton::Etsi::DataFetcher#save happens to
    # index on, and every record in the corpus carries exactly one. Keying on
    # `primary` instead means a record that ever carries two still indexes under
    # the identifier the client searches for.
    it "picks the primary docidentifier, not the first one" do
      in_workdir("data/a.yaml" => doc(id130, [{ "content" => "3GPP TS 33.501", "type" => "3GPP" }])) do
        expect(described_class.rows.first[:id]).to eq(id130)
      end
    end

    it "ignores docnumber, which is not what the fetcher indexes on" do
      in_workdir("data/a.yaml" => { "docnumber" => "ETSI WRONG 1 V1.1.1 (2000-01)",
                                    "docidentifier" => [{ "content" => id130, "primary" => true }] }) do
        expect(described_class.rows.first[:id]).to eq(id130)
      end
    end

    # Every data file must reach the index. Skipping one silently is the failure
    # that produced metanorma/metanorma-pdfa#95, so it is fatal, not a warning.
    it "raises, naming the file, when a document has no primary docidentifier" do
      in_workdir("data/a.yaml" => { "docidentifier" => [{ "content" => id130 }] },
                 "data/b.yaml" => doc(id130)) do
        expect { described_class.rows }
          .to raise_error(EtsiIndexBuilder::Error, %r{data/a\.yaml})
      end
    end

    it "raises, after reporting why, when a document is unparseable" do
      in_workdir("data/a.yaml" => doc(id130),
                 "data/bad.yaml" => "docidentifier: [unterminated\n") do
        expect { expect { described_class.rows }.to raise_error(EtsiIndexBuilder::Error, %r{data/bad\.yaml}) }
          .to output(/data\/bad\.yaml: Psych::SyntaxError/).to_stderr
      end
    end

    # ETSI dates are `at: 2004-06`, which YAML reads as a string, but one record
    # with a full `2004-06-15` would raise Psych::DisallowedClass under a bare
    # safe_load and take the whole crawl with it.
    it "tolerates a document carrying a real date" do
      in_workdir("data/a.yaml" => doc(id130).merge("date" => [{ "at" => Date.new(2026, 8, 1) }])) do
        expect(described_class.rows.first[:id]).to eq(id130)
      end
    end
  end

  describe ".build_index_v1" do
    it "writes plain string ids, the format the released relaton-etsi reads" do
      in_workdir("data/a.yaml" => doc(id130)) do
        described_class.build_index_v1
        expect(File.read("index-v1.yaml"))
          .to eq("---\n- :id: #{id130}\n  :file: data/a.yaml\n")
      end
    end

    # metanorma/metanorma-pdfa#95: index-v1 froze on 2026-07-15, so it still
    # named the superseded V1.2.1 file that the crawl had since deleted, and did
    # not name the V1.3.0 file that replaced it. The released client resolved the
    # dead row, got a 404 for the data file and reported "Not found".
    it "drops rows whose data file is gone and adds the files that replaced them" do
      in_workdir(v130 => doc(id130),
                 "index-v1.yaml" => [{ id: id121, file: v121 }]) do
        described_class.build_index_v1
        rows = YAML.safe_load_file("index-v1.yaml", permitted_classes: [Symbol])
        expect(rows).to eq([{ id: id130, file: v130 }])
        expect(rows.map { |r| r[:file] }).not_to include(v121)
      end
    end

    it "rebuilds from data/, not from the index-v1 it overwrites" do
      in_workdir("data/a.yaml" => doc(id130),
                 "index-v1.yaml" => [{ id: "ETSI EN 999 999 V1.1.1 (1999-01)", file: "data/gone.yaml" }]) do
        expect(described_class.build_index_v1.map { |r| r[:file] }).to eq(["data/a.yaml"])
      end
    end

    # A short data/ walk must not publish a truncated index.
    it "writes nothing when a document cannot be indexed" do
      in_workdir("data/a.yaml" => doc(id130),
                 "data/b.yaml" => { "title" => "no docnumber here" }) do
        expect { described_class.build_index_v1 }.to raise_error(EtsiIndexBuilder::Error)
        expect(File.exist?("index-v1.yaml")).to be(false)
      end
    end
  end
end
