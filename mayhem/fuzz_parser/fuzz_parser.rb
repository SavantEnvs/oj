# Oj::Parser (parser.c): the :usual, :validate and :saj delegates, plus a few of the usual
# parser's options, each on a fresh parser so no state carries between inputs.
class NullSaj
  def hash_start(key); end
  def hash_end(key); end
  def array_start(key); end
  def array_end(key); end
  def add_value(value, key); end
  def error(message, line, column); end
end

->(s) {
  # Mayhem's symbolic executor aborts ("SE exited abnormally") on numbers with huge exponents, failing the whole run.
  next if s.match?(/[0-9][eE][-+]?[0-9]{4,}/)
  [
    -> { Oj::Parser.new(:usual) },
    -> { Oj::Parser.new(:usual, symbol_keys: true, cache_keys: true, cache_strings: 5, capacity: 100) },
    -> { Oj::Parser.new(:usual, decimal: :bigdecimal, omit_null: true, create_id: '^') },
    -> { Oj::Parser.new(:usual, decimal: :float, class_cache: true, missing_class: :ignore) },
    -> { Oj::Parser.new(:validate) },
    -> { Oj::Parser.new(:saj).tap { |p| p.handler = NullSaj.new } },
    -> { Oj::Parser.new(:saj).tap { |p| p.handler = NullSaj.new; p.cache_keys = true; p.cache_strings = 4 } },
    -> { Oj::Parser.new(:usual).tap { |p| p.just_one = true } },
  ].each do |mk|
    begin
      mk.call.parse(s)
    rescue Exception
    end
  end
  begin
    Oj::Parser.new(:usual).load(StringIO.new(s))
  rescue Exception
  end
}
