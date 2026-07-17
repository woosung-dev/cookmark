# og:image 메타 추출 — stdlib HTMLParser라 잘린·불량 HTML에도 예외 없이 동작한다 (#102)
from html.parser import HTMLParser


class OgImageParser(HTMLParser):
    """첫 번째 비어있지 않은 og:image content를 잡는다. 스트리밍 feed 후 og_image를 읽는다.

    property="og:image"가 표준이지만 name="og:image" 오기도 흔해 둘 다 받는다.
    og:image:secure_url·twitter:image는 미채택 — 타깃 사이트(네이버·티스토리·만개의레시피·
    유튜브)가 전부 표준 og:image를 낸다.
    """

    def __init__(self) -> None:
        super().__init__()
        self.og_image: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.og_image is not None or tag != "meta":
            return
        attributes = dict(attrs)
        if "og:image" not in (attributes.get("property"), attributes.get("name")):
            return
        content = (attributes.get("content") or "").strip()
        if content:
            self.og_image = content


def extract_og_image(html: str) -> str | None:
    """한 번에 파싱하는 편의 함수 — 서비스는 OgImageParser를 청크 단위로 직접 쓴다."""
    parser = OgImageParser()
    parser.feed(html)
    return parser.og_image
