"""Copy the report template and add the styles pandoc's docx writer uses.

The template defines no table style, so pandoc tables would have no borders.
This adds bordered "Table", plus "Table Caption" and "Image Caption", to a
copy of the template that pandoc then uses as its reference document.

Usage: python3 make-reference-docx.py <template.docx> <output.docx>
"""
import shutil
import sys
import zipfile

STYLES = """
<w:style w:type="table" w:styleId="Table"><w:name w:val="Table"/><w:basedOn w:val="TableNormal"/><w:uiPriority w:val="59"/><w:qFormat/>
<w:pPr><w:spacing w:before="40" w:after="40"/></w:pPr><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>
<w:tblPr><w:tblBorders>
<w:top w:val="single" w:sz="4" w:space="0" w:color="808080"/><w:left w:val="single" w:sz="4" w:space="0" w:color="808080"/>
<w:bottom w:val="single" w:sz="4" w:space="0" w:color="808080"/><w:right w:val="single" w:sz="4" w:space="0" w:color="808080"/>
<w:insideH w:val="single" w:sz="4" w:space="0" w:color="808080"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="808080"/>
</w:tblBorders><w:tblCellMar><w:left w:w="80" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar></w:tblPr>
<w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/></w:tcPr></w:tblStylePr>
</w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="TableCaption"><w:name w:val="Table Caption"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
<w:pPr><w:keepNext/><w:spacing w:before="120" w:after="60"/></w:pPr><w:rPr><w:b/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="ImageCaption"><w:name w:val="Image Caption"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
<w:pPr><w:jc w:val="center"/><w:spacing w:before="60" w:after="200"/></w:pPr><w:rPr><w:i/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="CaptionedFigure"><w:name w:val="Captioned Figure"/><w:basedOn w:val="Normal"/><w:qFormat/>
<w:pPr><w:keepNext/><w:jc w:val="center"/></w:pPr></w:style>
"""


def main(template: str, output: str) -> None:
    shutil.copyfile(template, output)
    with zipfile.ZipFile(template) as source:
        styles = source.read("word/styles.xml").decode("utf-8")
        entries = {name: source.read(name) for name in source.namelist()}
    for style_id in ("Table", "TableCaption", "ImageCaption", "CaptionedFigure"):
        if f'w:styleId="{style_id}"' in styles:
            raise SystemExit(f"template already defines {style_id}; update this script")
    entries["word/styles.xml"] = styles.replace("</w:styles>", STYLES + "</w:styles>").encode("utf-8")
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as target:
        for name, data in entries.items():
            target.writestr(name, data)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
