import json
import os
import re
from typing import Optional

import httpx


async def generate_connection_summaries(
    profile1: dict,
    profile2: dict,
    match_percentage: float,
) -> dict[str, Optional[str]]:
    """Call Gemini 2.0 Flash via OpenRouter to generate connection summaries.

    Returns dict with keys: uid1_summary, uid2_summary, notification_message.
    All values are None on failure.
    """
    empty = {"uid1_summary": None, "uid2_summary": None, "notification_message": None}
    api_key = os.getenv("OPENROUTER_API_KEY")
    if not api_key:
        return empty

    def _profile_text(p: dict) -> str:
        identity = p.get("identity", {})
        skills = p.get("skills", {})
        project = p.get("project") or {}
        possessed = [s["name"] for s in skills.get("possessed", [])]
        needed = [s["name"] for s in skills.get("needed", [])]
        return (
            f"Name: {identity.get('full_name', 'Unknown')}\n"
            f"University: {identity.get('university', 'N/A')}\n"
            f"Major: {', '.join(identity.get('major', []))}\n"
            f"Focus areas: {', '.join(p.get('focus_areas', []))}\n"
            f"Project: {project.get('one_liner', 'N/A')}\n"
            f"Industry: {', '.join(project.get('industry', []))}\n"
            f"Skills possessed: {', '.join(possessed)}\n"
            f"Skills needed: {', '.join(needed)}"
        )

    prompt = f"""You are matching two students for collaboration. Their match score is {match_percentage:.0f}%.

USER A:
{_profile_text(profile1)}

USER B:
{_profile_text(profile2)}

Generate:
1. "uid1_summary": 2-3 sentences about User A written FOR User B. Highlight what User A brings that User B needs.
2. "uid2_summary": 2-3 sentences about User B written FOR User A. Highlight what User B brings that User A needs.
3. "notification_message": Short (<100 chars) notification text like "You matched with [Name]! They know [skill]."

Return ONLY valid JSON with these three keys. No markdown fences."""

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                "https://openrouter.ai/api/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": "google/gemini-2.0-flash-001",
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.7,
                },
            )
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"]

            # Strip markdown fences if present
            content = re.sub(r"^```(?:json)?\s*", "", content.strip())
            content = re.sub(r"\s*```$", "", content.strip())

            data = json.loads(content)
            return {
                "uid1_summary": data.get("uid1_summary"),
                "uid2_summary": data.get("uid2_summary"),
                "notification_message": data.get("notification_message"),
            }
    except Exception:
        return empty
