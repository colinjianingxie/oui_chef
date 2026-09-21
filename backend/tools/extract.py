"""Extract public recipe evidence from an already safely fetched HTML file. No network."""
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path


class Page(HTMLParser):
    def __init__(self, youtube=False):
        super().__init__(convert_charrefs=True)
        self.parts, self.structured, self.links, self.meta = [], [], [], {}
        self.script = None
        self.script_text = []
        self.hidden = 0
        self.youtube = youtube
        self.video = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ('script', 'style', 'noscript', 'svg'):
            self.hidden += 1
        if tag == 'script':
            self.script = attrs.get('type', '')
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
            if self.youtube:
                match = re.search(r'(?:var\s+)?ytInitialPlayerResponse\s*=\s*', ''.join(self.script_text))
                if match:
                    try:
                        self.video = json.JSONDecoder().raw_decode(''.join(self.script_text)[match.end():])[0]
                    except ValueError:
                        pass
            self.script = None
        if tag in ('script', 'style', 'noscript', 'svg'):
            self.hidden = max(0, self.hidden - 1)

    def handle_data(self, data):
        if self.script is not None:
            self.script_text.append(data)
        if not self.hidden and data.strip():
            self.parts.append(data.strip())

    def result(self):
        result = {'text': '\n'.join(self.parts)[:80000], 'structured': self.structured[:10],
                'metadata': self.meta, 'imageURL': self.meta.get('og:image'), 'links': self.links[:100]}
        details = self.video.get('videoDetails', {})
        if details:
            result.update(title=details.get('title'), creator=details.get('author'), description=details.get('shortDescription', ''))
            result['text'] = '\n'.join(filter(None, [details.get('title'), details.get('author'), details.get('shortDescription')]))[:80000]
            images = details.get('thumbnail', {}).get('thumbnails', [])
            if images:
                result['imageURL'] = images[-1].get('url')
        if self.youtube:
            result['captionTracks'] = self.video.get('captions', {}).get('playerCaptionsTracklistRenderer', {}).get('captionTracks', [])
        return result


if __name__ == '__main__':
    page = Page(youtube="--youtube" in sys.argv[2:])
    page.feed(Path(sys.argv[1]).read_text(errors='replace'))
    print(json.dumps(page.result(), ensure_ascii=False))
