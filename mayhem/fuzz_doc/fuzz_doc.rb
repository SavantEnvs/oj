# Oj::Doc (fast.c): open the document, then walk it with the path API.
def walk(doc, depth)
  return if depth > 6
  doc.type
  doc.where
  doc.path
  doc.local_key
  doc.fetch
  doc.size
  doc.each_child do |d|
    d.local_key
    d.type
    walk(d, depth + 1)
  end
end

->(s) {
  begin
    Oj::Doc.open(s) do |doc|
      doc.where?
      walk(doc, 0)
      doc.each_leaf { |d| d.where?; d.fetch }
      doc.each_value { |v| v }
      doc.exists?('/1')
      doc.exists?('/a/b')
      doc.type('/1')
      doc.fetch('/1/2', 'dflt')
      doc.fetch('/a/b/c')
      doc.move('/1') rescue nil
      doc.home
      doc.move('/a') rescue nil
      doc.dump
      doc.dump('/1')
      doc.each_child('/') { |d| d.fetch }
    end
  rescue Exception
  end
}
