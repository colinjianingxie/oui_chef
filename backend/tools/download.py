"""Download one selected HLS stream through the importer's public-IP-only proxy."""
import json
import sys
from pathlib import Path
from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError


def bounded(progress):
    if progress.get('downloaded_bytes', 0) > 40_000_000:
        raise DownloadError('Source exceeds import size limit.')


if __name__ == '__main__':
    info = json.loads(Path(sys.argv[1]).read_text())
    if info.get('protocol') != 'm3u8_native' or not info.get('url', '').startswith('https://'):
        raise ValueError('Expected a public HTTPS HLS stream.')
    with YoutubeDL({'proxy': sys.argv[3], 'outtmpl': sys.argv[2], 'quiet': True,
                    'cachedir': False, 'enable_file_urls': False,
                    'hls_prefer_native': True, 'external_downloader': {'default': 'native'},
                    'socket_timeout': 15, 'retries': 0, 'fragment_retries': 0,
                    'skip_unavailable_fragments': False, 'max_filesize': 40_000_000,
                    'progress_hooks': [bounded]}) as downloader:
        downloader.process_info({'id': 'source', 'title': 'Source media', **info})
