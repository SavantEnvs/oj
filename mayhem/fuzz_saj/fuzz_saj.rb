# The event-driven parsers: Oj.saj_parse (saj.c) and Oj.sc_parse (scp.c), from a String and a
# StringIO. The handlers record nothing, so each input is independent.
class NullSaj < Oj::Saj
  def hash_start(key); end
  def hash_end(key); end
  def array_start(key); end
  def array_end(key); end
  def add_value(value, key); end
  def error(message, line, column); end
end

class NullSc < Oj::ScHandler
  def hash_start; {}; end
  def hash_end; end
  def hash_key(key); key; end
  def hash_set(h, key, value); end
  def array_start; []; end
  def array_end; end
  def array_append(a, value); end
  def add_value(value); end
end

class BareSc < Oj::ScHandler
  def add_value(value); end
end

->(s) {
  # Mayhem's symbolic executor aborts ("SE exited abnormally") on numbers with huge exponents, failing the whole run.
  next if s.match?(/[0-9][eE][-+]?[0-9]{4,}/)
  [
    -> { Oj.saj_parse(NullSaj.new, s) },
    -> { Oj.saj_parse(NullSaj.new, StringIO.new(s)) },
    -> { Oj.sc_parse(NullSc.new, s) },
    -> { Oj.sc_parse(NullSc.new, StringIO.new(s)) },
    -> { Oj.sc_parse(BareSc.new, s) },
  ].each do |f|
    begin
      f.call
    rescue Exception
    end
  end
}
