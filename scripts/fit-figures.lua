-- Size every image to fit an A4 page with 1-inch margins, leaving room for
-- the caption. PNGs from render-diagrams.sh are rendered at 2x, so their
-- natural size is pixels / 192 inches; never enlarge beyond that.
local MAX_W_IN, MAX_H_IN, PX_PER_IN = 6.2, 8.4, 192

function Image(el)
  if el.attributes.width or el.attributes.height then return nil end
  local _, contents = pandoc.mediabag.fetch(el.src)
  if not contents then return nil end
  local ok, size = pcall(pandoc.image.size, contents)
  if not ok then return nil end
  local w, h = size.width / PX_PER_IN, size.height / PX_PER_IN
  local scale = math.min(1, MAX_W_IN / w, MAX_H_IN / h)
  el.attributes.width = string.format('%.2fin', w * scale)
  return el
end
