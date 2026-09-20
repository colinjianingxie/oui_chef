"""Extract public recipe evidence from an already safely fetched HTML file. No network."""
import json
import sys
from html.parser import HTMLParser
from pathlib import Path


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.structured, self.links, self.meta = [], [], [], {}
        self.script = None
        self.script_text = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ('script', 'style', 'noscript', 'svg'):
            self.hidden += 1
        if tag == 'script':
            self.script = attrs.get('type')
            self.script_text = []
        if tag == 'meta':
            self.meta[attrs.get('property', attrs.get('name', ''))] = attrs.get('content', '')
        if tag == 'a' and attrs.get('href'):
            self.links.append(attrs['href'])

    def handle_endtag(self, tag):
        if tag == 'script':
            if self.script == 'application/ld+json':
                try:
                    self.structured.append(json.loads(''.join(self.script_text)))
                except ValueError:
                    pass
            self.script = None
        if tag in ('script', 'style', 'noscript', 'svg'):
            self.hidden = max(0, self.hidden - 1)

    def handle_data(self, data):
        if self.script == 'application/ld+json':
            self.script_text.append(data)
        if not self.hidden and data.strip():
            self.parts.append(data.strip())

    def result(self):
        return {'text': '\n'.join(self.parts)[:80000], 'structured': self.structured[:10],
                'metadata': self.meta, 'imageURL': self.meta.get('og:image'), 'links': self.links[:100]}


if __name__ == '__main__':
    page = Page()
    page.feed(Path(sys.argv[1]).read_text(errors='replace'))
    print(json.dumps(page.result(), ensure_ascii=False))
