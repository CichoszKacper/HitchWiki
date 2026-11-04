#!/usr/bin/env python3
"""Shrink a MediaWiki XML dump to the latest revision of each page, optionally filtering namespaces.

Usage: python3 slim_dump.py hitchwiki-full-en.xml output/hitchwiki-latest.xml [--ns 0,10,14]
Works for any export version (0.10, 0.11, ...) and language: the XML namespace and xml:lang are
taken from the input. The output is still a valid MediaWiki export, so WikiExtractor, mwxml,
importDump.php etc. all read it.
"""
import argparse, xml.etree.ElementTree as ET

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('dst')
ap.add_argument('--ns', default='0,10,14', help="namespaces to keep ('all' for every namespace)")
a = ap.parse_args()
keep = None if a.ns == 'all' else set(a.ns.split(','))

XML_LANG = '{http://www.w3.org/XML/1998/namespace}lang'
NS = None
kept = 0
with open(a.dst, 'w', encoding='utf-8') as out:
    for ev, el in ET.iterparse(a.src, events=('start', 'end')):
        if NS is None and ev == 'start':
            # Root <mediawiki xmlns="http://www.mediawiki.org/xml/export-0.11/" version="0.11" xml:lang="pl">
            uri = el.tag[1:].split('}')[0] if el.tag.startswith('{') else ''
            NS = '{%s}' % uri if uri else ''
            ET.register_namespace('', uri)
            out.write('<mediawiki xmlns="%s" version="%s" xml:lang="%s">\n'
                      % (uri, el.get('version', '0.11'), el.get(XML_LANG, 'en')))
            continue
        if ev != 'end':
            continue
        if el.tag == NS + 'siteinfo':
            out.write(ET.tostring(el, encoding='unicode')); el.clear()
        elif el.tag == NS + 'page':
            if keep is None or el.findtext(NS + 'ns') in keep:
                revs = el.findall(NS + 'revision')
                for r in revs[:-1]:
                    el.remove(r)
                out.write(ET.tostring(el, encoding='unicode')); kept += 1
            el.clear()
    out.write('</mediawiki>\n')
print('kept', kept, 'pages')
