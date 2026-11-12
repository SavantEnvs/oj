# Oj.load across every parse mode, from a String and from a StringIO (the reader.c path).
OPTS = [
  { mode: :strict },
  { mode: :strict, symbol_keys: true, bigdecimal_load: :bigdecimal },
  { mode: :null },
  { mode: :compat },
  { mode: :compat, symbol_keys: true, decimal_class: BigDecimal },
  { mode: :object },
  { mode: :custom },
  { mode: :rails },
  { mode: :wab },
].freeze

->(s) {
  OPTS.each do |o|
    begin
      Oj.load(s, o)
    rescue Exception
    end
  end
  [{ mode: :strict }, { mode: :compat }, { mode: :object }].each do |o|
    begin
      Oj.load(StringIO.new(s), o)
    rescue Exception
    end
  end
  begin
    Oj.safe_load(s)
  rescue Exception
  end
}
