defmodule Gettext.MergerTest do
  use ExUnit.Case, async: true

  alias Gettext.Merger
  alias Gettext.PO
  alias Gettext.PO.Translation
  alias Gettext.PO.PluralTranslation

  @gettext_config []
  @opts fuzzy: true, fuzzy_threshold: 0.8
  @autogenerated_flags MapSet.new(["elixir-format"])
  @pot_path "../../tmp/" |> Path.expand(__DIR__) |> Path.relative_to_cwd()

  describe "merge/2" do
    test "headers from the old file are kept" do
      old_po = %PO{headers: [~S(Language: it\n), ~S(My-Header: my-value\n)]}
      new_pot = %PO{headers: ["foo"]}

      assert Merger.merge(old_po, new_pot, "en", @opts).headers == old_po.headers
    end

    test "obsolete translations are discarded (even the manually entered ones)" do
      old_po = %PO{
        translations: [
          %Translation{msgid: "obs_auto", msgstr: "foo", flags: @autogenerated_flags},
          %Translation{msgid: "obs_manual", msgstr: "foo"},
          %Translation{msgid: "tomerge", msgstr: "foo"}
        ]
      }

      new_pot = %PO{translations: [%Translation{msgid: "tomerge", msgstr: ""}]}

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      assert t.msgid == "tomerge"
      assert t.msgstr == "foo"
    end

    test "when translations match, the msgstr of the old one is preserved" do
      old_po = %PO{translations: [%Translation{msgid: "foo", msgstr: "bar"}]}
      new_pot = %PO{translations: [%Translation{msgid: "foo", msgstr: ""}]}

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      assert t.msgid == "foo"
      assert t.msgstr == "bar"
    end

    test "when translations match, existing translator comments are preserved" do
      # Note that the new translation *should* not have any translator comments
      # (comes from a POT file).
      old_po = %PO{translations: [%Translation{msgid: "foo", comments: ["# existing comment"]}]}
      new_pot = %PO{translations: [%Translation{msgid: "foo", comments: ["# new comment"]}]}

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      assert t.msgid == "foo"
      assert t.comments == ["# existing comment"]
    end

    test "when translations match, existing extracted comments are replaced by new ones" do
      old_po = %PO{
        translations: [
          %Translation{
            msgid: "foo",
            extracted_comments: ["#. existing comment", "#. other existing comment"]
          }
        ]
      }

      new_pot = %PO{
        translations: [%Translation{msgid: "foo", extracted_comments: ["#. new comment"]}]
      }

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      assert t.extracted_comments == ["#. new comment"]
    end

    test "when translations match, existing references are replaced by new ones" do
      old_po = %PO{translations: [%Translation{msgid: "foo", references: [{"foo.ex", 1}]}]}
      new_pot = %PO{translations: [%Translation{msgid: "foo", references: [{"bar.ex", 1}]}]}

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      assert t.references == [{"bar.ex", 1}]
    end

    test "when translations match, existing flags are replaced by new ones" do
      old_po = %PO{translations: [%Translation{msgid: "foo"}]}

      new_pot = %PO{
        translations: [%Translation{msgid: "foo", flags: @autogenerated_flags}]
      }

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      assert t.flags == @autogenerated_flags
    end

    test "new translations are fuzzy-matched against obsolete translations" do
      old_po = %PO{
        translations: [
          %Translation{
            msgid: "hello world!",
            msgstr: ["foo"],
            comments: ["# existing comment"],
            extracted_comments: ["#. existing comment"],
            references: [{"foo.ex", 1}]
          }
        ]
      }

      new_pot = %PO{
        translations: [
          %Translation{
            msgid: "hello worlds!",
            references: [{"foo.ex", 2}],
            extracted_comments: ["#. new comment"],
            flags: MapSet.new(["my-flag"])
          }
        ]
      }

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)

      assert t.msgid == "hello worlds!"
      assert t.msgstr == ["foo"]
      assert t.comments == ["# existing comment"]
      assert t.extracted_comments == ["#. new comment"]
      assert t.references == [{"foo.ex", 2}]
      assert t.flags == MapSet.new(["my-flag", "fuzzy"])
    end

    test "exact matches have precedence over fuzzy matches" do
      old_po = %PO{
        translations: [
          %Translation{msgid: ["hello world!"], msgstr: ["foo"]},
          %Translation{msgid: ["hello worlds!"], msgstr: ["bar"]}
        ]
      }

      new_pot = %PO{translations: [%Translation{msgid: ["hello world!"]}]}

      # Let's check that the "hello worlds!" translation is discarded even if it's
      # a fuzzy match for "hello world!".
      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      refute "fuzzy" in t.flags
      assert t.msgid == ["hello world!"]
      assert t.msgstr == ["foo"]
    end

    test "exact matches do not prevent fuzzy matches for other translations" do
      old_po = %PO{translations: [%Translation{msgid: ["hello world"], msgstr: ["foo"]}]}

      # "hello world" will match exactly.
      # "hello world!" should still get a fuzzy match.
      new_pot = %PO{
        translations: [
          %Translation{msgid: ["hello world"]},
          %Translation{msgid: ["hello world!"]}
        ]
      }

      assert %PO{translations: [t1, t2]} = Merger.merge(old_po, new_pot, "en", @opts)

      assert t1.msgid == ["hello world"]
      assert t1.msgstr == ["foo"]
      refute "fuzzy" in t1.flags

      assert t2.msgid == ["hello world!"]
      assert t2.msgstr == ["foo"]
      assert "fuzzy" in t2.flags
    end

    test "multiple translations can fuzzy match against a single translation" do
      old_po = %PO{translations: [%Translation{msgid: ["hello world"], msgstr: ["foo"]}]}

      new_pot = %PO{
        translations: [
          %Translation{msgid: ["hello world 1"]},
          %Translation{msgid: ["hello world 2"]}
        ]
      }

      assert %PO{translations: [t1, t2]} = Merger.merge(old_po, new_pot, "en", @opts)

      assert t1.msgid == ["hello world 1"]
      assert t1.msgstr == ["foo"]
      assert "fuzzy" in t1.flags

      assert t2.msgid == ["hello world 2"]
      assert t2.msgstr == ["foo"]
      assert "fuzzy" in t2.flags
    end

    test "filling in a fuzzy translation preserves references" do
      old_po = %PO{
        translations: [
          %Translation{
            msgid: ["hello world!"],
            msgstr: ["foo"],
            comments: ["# old comment"],
            references: [{"old_file.txt", 1}]
          }
        ]
      }

      new_pot = %PO{
        translations: [%Translation{msgid: ["hello worlds!"], references: [{"new_file.txt", 2}]}]
      }

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      assert MapSet.member?(t.flags, "fuzzy")
      assert t.msgid == ["hello worlds!"]
      assert t.msgstr == ["foo"]
      assert t.comments == ["# old comment"]
      assert t.references == [{"new_file.txt", 2}]
    end

    test "simple translations can be a fuzzy match for plurals" do
      old_po = %PO{
        translations: [
          %Translation{
            msgid: ["Here are {count} cocoa balls."],
            msgstr: ["Hier sind {count} Kakaokugeln."],
            comments: ["# Guyanese Cocoballs"],
            references: [{"old_file.txt", 1}]
          }
        ]
      }

      new_pot = %PO{
        translations: [
          %PluralTranslation{
            msgid: ["Here is a cocoa ball."],
            msgid_plural: ["Here are {count} cocoa balls."],
            references: [{"new_file.txt", 2}]
          }
        ]
      }

      assert %PO{translations: [t]} = Merger.merge(old_po, new_pot, "en", @opts)
      assert MapSet.member?(t.flags, "fuzzy")
      assert t.msgid == ["Here is a cocoa ball."]
      assert t.msgid_plural == ["Here are {count} cocoa balls."]
      assert t.msgstr[0] == ["Hier sind {count} Kakaokugeln."]
      assert t.comments == ["# Guyanese Cocoballs"]
      assert t.references == [{"new_file.txt", 2}]
    end

    test "if there's a Plural-Forms header, it's used to determine number of plural forms" do
      old_po = %PO{
        headers: [~s(Plural-Forms:  nplurals=3)],
        translations: []
      }

      new_pot = %PO{
        translations: [
          %Translation{msgid: "a"},
          %PluralTranslation{msgid: "b", msgid_plural: "bs"}
        ]
      }

      assert %PO{translations: [t, pt]} = Merger.merge(old_po, new_pot, "en", @opts)

      assert t.msgid == "a"

      assert pt.msgid == "b"
      assert pt.msgid_plural == "bs"
      assert pt.msgstr == %{0 => [""], 1 => [""], 2 => [""]}
    end

    test "plural forms can be specified as an option" do
      old_po = %PO{translations: []}

      new_pot = %PO{
        translations: [
          %Translation{msgid: "a"},
          %PluralTranslation{msgid: "b", msgid_plural: "bs"}
        ]
      }

      opts = [plural_forms: 1] ++ @opts
      assert %PO{translations: [t, pt]} = Merger.merge(old_po, new_pot, "en", opts)

      assert t.msgid == "a"

      assert pt.msgid == "b"
      assert pt.msgid_plural == "bs"
      assert pt.msgstr == %{0 => [""]}
    end
  end

  test "new_po_file/2" do
    pot_path = Path.join(@pot_path, "new_po_file.pot")
    new_po_path = Path.join(@pot_path, "it/LC_MESSAGES/new_po_file.po")

    write_file(pot_path, """
    ## Stripme!
    # A comment
    msgid "foo"
    msgstr "bar"

    msgid "plural"
    msgid_plural "plurals"
    msgstr[0] ""
    msgstr[1] ""
    """)

    opts = [plural_forms: 1] ++ @opts
    merged = Merger.new_po_file(new_po_path, pot_path, "it", opts, @gettext_config)
    merged = IO.iodata_to_binary(merged)

    assert String.ends_with?(merged, ~S"""
           msgid ""
           msgstr ""
           "Language: it\n"
           "Plural-Forms: nplurals=1\n"

           # A comment
           msgid "foo"
           msgstr "bar"

           msgid "plural"
           msgid_plural "plurals"
           msgstr[0] ""
           """)

    assert String.starts_with?(merged, "## `msgid`s in this file come from POT")
  end

  defp write_file(path, contents) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, contents)
  end
end
