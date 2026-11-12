# Parse the input as JSON, then re-serialize the result in every dump mode and with the
# formatting options that change dump.c's code paths. Inputs that do not parse are not dumped.
DUMP_OPTS = [
  { mode: :strict },
  { mode: :null, indent: 2 },
  { mode: :compat, indent: 1, space: ' ', object_nl: "\n", array_nl: "\n" },
  { mode: :compat, escape_mode: :ascii },
  { mode: :compat, escape_mode: :xss_safe },
  { mode: :custom, indent: 2, time_format: :xmlschema, bigdecimal_as_decimal: true },
  { mode: :rails },
  { mode: :wab },
  { mode: :object, indent: 2 },
  { mode: :strict, escape_mode: :unicode_xss, float_precision: 5 },
].freeze

->(s) {
  begin
    obj = Oj.load(s, mode: :strict, bigdecimal_load: :auto)
  rescue Exception
    next
  end
  DUMP_OPTS.each do |o|
    begin
      Oj.dump(obj, o)
    rescue Exception
    end
  end
  begin
    Oj.generate(obj)
  rescue Exception
  end
  begin
    w = Oj::StringWriter.new(mode: :compat)
    w.push_array
    w.push_value(obj)
    w.pop_all
    w.to_s
  rescue Exception
  end
}
