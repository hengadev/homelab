import os
import threading
from contextlib import contextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel

app = FastAPI(title="Anki API", docs_url=None, redoc_url=None)

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

_API_KEY = os.environ.get("ANKI_API_KEY", "")
if not _API_KEY:
    raise RuntimeError("ANKI_API_KEY environment variable is required")

_key_header = APIKeyHeader(name="X-API-Key", auto_error=True)


def _require_key(key: str = Security(_key_header)) -> None:
    if key != _API_KEY:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")


# ---------------------------------------------------------------------------
# Collection management
# ---------------------------------------------------------------------------

SYNC_BASE = os.environ.get("SYNC_BASE", "/anki-data")

_lock = threading.Lock()


def _find_collection() -> Path:
    for path in Path(SYNC_BASE).rglob("collection.anki2"):
        return path
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="No Anki collection found. Sync your Anki client to the server first.",
    )


@contextmanager
def _open_collection(path: Path):
    from anki.collection import Collection

    try:
        col = Collection(str(path))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Cannot open collection (may be locked during sync): {exc}",
        ) from exc

    try:
        yield col
        col.save()
    finally:
        col.close()


def _get_or_create_deck(col, name: str) -> int:
    for deck in col.decks.all_names_and_ids():
        if deck.name == name:
            return deck.id
    result = col.decks.add_normal_deck_with_name(name)
    return result.id


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------


class DeckCreate(BaseModel):
    name: str


class CardCreate(BaseModel):
    deck: str
    type: str  # "basic" | "cloze"
    front: str  # for cloze: full text with {{c1::...}} markers
    back: str = ""


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/decks", dependencies=[Security(_require_key)])
def list_decks():
    col_path = _find_collection()
    with _lock:
        with _open_collection(col_path) as col:
            decks = list(col.decks.all_names_and_ids())
    return [{"id": d.id, "name": d.name} for d in decks]


@app.post("/decks", status_code=status.HTTP_201_CREATED, dependencies=[Security(_require_key)])
def create_deck(body: DeckCreate):
    col_path = _find_collection()
    with _lock:
        with _open_collection(col_path) as col:
            did = _get_or_create_deck(col, body.name)
    return {"id": did, "name": body.name}


@app.post("/cards", status_code=status.HTTP_201_CREATED, dependencies=[Security(_require_key)])
def create_card(body: CardCreate):
    if body.type not in ("basic", "cloze"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="type must be 'basic' or 'cloze'",
        )

    col_path = _find_collection()

    with _lock:
        with _open_collection(col_path) as col:
            did = _get_or_create_deck(col, body.deck)

            notetype_name = "Basic" if body.type == "basic" else "Cloze"
            notetype = col.models.by_name(notetype_name)
            if notetype is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Note type '{notetype_name}' not found. Was it renamed or deleted from the collection?",
                )

            note = col.new_note(notetype)
            if body.type == "basic":
                note["Front"] = body.front
                note["Back"] = body.back
            else:
                note["Text"] = body.front

            col.add_note(note, did)

    return {"id": note.id, "deck": body.deck, "type": body.type}
