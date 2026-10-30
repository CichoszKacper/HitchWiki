#!/usr/bin/env python3
"""Shrink a full-history MediaWiki XML dump to latest revision only, optionally filtering namespaces.

Usage: python3 slim_dump.py hitchwiki-full-en.xml output/hitchwiki-latest.xml [--ns 0,10,14]
The output is still a valid MediaWiki export, so WikiExtractor, mwxml, importDump.php etc. all read it.
"""
import argparse, xml.etree.ElementTree as ET

NS_URI = 'http://www.mediawiki.org/xml/export-0.11/'
NS = '{%s}' % NS_URI
ET.register_namespace('', NS_URI)

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('dst')
ap.add_argument('--ns', default='0,10,14', help="namespaces to keep ('all' for every namespace)")
a = ap.parse_args()
keep = None if a.ns == 'all' else set(a.ns.split(','))

kept = 0
with open(a.dst, 'w', encoding='utf-8') as out:
    out.write('<mediawiki xmlns="%s" version="0.11" xml:lang="en">\n' % NS_URI)
    for ev, el in ET.iterparse(a.src, events=('end',)):
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
