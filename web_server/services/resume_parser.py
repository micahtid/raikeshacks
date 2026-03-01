import json
import os
from io import BytesIO
from typing import Optional

import httpx
from pydantic import BaseModel


class ParsedResume(BaseModel):
    university: Optional[str] = None
    graduation_year: Optional[int] = None
    major: list[str] = []
    minor: list[str] = []
    skills: list[str] = []
    industry: list[str] = []
    project_one_liner: Optional[str] = None


def extract_text_from_pdf(data: bytes) -> str:
    from PyPDF2 import PdfReader

    reader = PdfReader(BytesIO(data))
    parts = []
    for page in reader.pages:
        text = page.extract_text()
        if text:
            parts.append(text)
    return "\n".join(parts)


def extract_text_from_docx(data: bytes) -> str:
    from docx import Document

    doc = Document(BytesIO(data))
    return "\n".join(p.text for p in doc.paragraphs if p.text.strip())


def extract_text(data: bytes, filename: str) -> str:
    lower = filename.lower()
    if lower.endswith(".pdf"):
        return extract_text_from_pdf(data)
    elif lower.endswith(".docx") or lower.endswith(".doc"):
        return extract_text_from_docx(data)
    else:
        raise ValueError(f"Unsupported file type: {filename}")


EXTRACTION_PROMPT = """Extract the following structured information from this resume text.
Return ONLY valid JSON with these fields:
- "university": string or null (the university/college name)
- "graduation_year": integer or null (expected or actual graduation year)
- "major": list of strings (major fields of study)
- "minor": list of strings (minor fields of study, empty list if none)
- "skills": list of strings (technical and professional skills)
- "industry": list of strings (industries/domains the person has experience in, e.g. "FinTech", "HealthTech", "AI/ML")
- "project_one_liner": string or null (a one-sentence summary of their most notable project)

Resume text:
"""


async def parse_resume(data: bytes, filename: str) -> ParsedResume:
    text = extract_text(data, filename)
    if not text.strip():
        return ParsedResume()

    api_key = os.getenv("OPENROUTER_API_KEY", "")
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY is not set")

    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            "https://openrouter.ai/api/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": "google/gemini-2.0-flash-001",
                "messages": [
                    {
                        "role": "user",
                        "content": EXTRACTION_PROMPT + text[:8000],
                    }
                ],
                "temperature": 0.1,
            },
        )
        resp.raise_for_status()

    body = resp.json()
    content = body["choices"][0]["message"]["content"]

    # Strip markdown fences if present
    content = content.strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1] if "\n" in content else content[3:]
    if content.endswith("```"):
        content = content[:-3]
    content = content.strip()

    try:
        parsed = json.loads(content)
    except json.JSONDecodeError:
        return ParsedResume()

    return ParsedResume(**{k: v for k, v in parsed.items() if k in ParsedResume.model_fields})
