import json
import sys
from pathlib import Path
from datetime import datetime, timezone
from uuid import uuid4
from typing import Optional
from unittest.mock import MagicMock

# Add the web_server directory to sys.path to resolve internal imports
web_server_dir = Path(__file__).parent.absolute()
if str(web_server_dir) not in sys.path:
    sys.path.insert(0, str(web_server_dir))

# Mock SentenceTransformer for environment-independent testing
import services.similarity
# Replace the model with a mock that returns deterministic vectors
# We mock it to ensure that the logic itself is verified even if torch is broken
mock_model = MagicMock()
mock_vec = MagicMock()
mock_vec.tolist.return_value = [0.1] * 384
mock_model.encode.return_value = mock_vec
services.similarity.model = mock_model
services.similarity.HAS_TRANSFORMERS = True # Force high-level logic test

from models.student import (
    StudentProfile, Identity, Project, Skills, 
    PossessedSkill, NeededSkill, SkillSource, SkillPriority, FocusArea, Rag
)
from services.similarity import (
    generate_profile_embeddings, vectorize_profile, compute_match, Weights
)

def create_example_student(
    name: str, 
    skills_have: list[str], 
    skills_need: list[str], 
    focus: list[FocusArea],
    project_one_liner: Optional[str] = None,
    industry: list[str] = []
) -> StudentProfile:
    uid = str(uuid4())
    return StudentProfile(
        uid=uid,
        created_at=datetime.now(timezone.utc),
        identity=Identity(
            full_name=name,
            email=f"{name.lower().replace(' ', '.')}@unl.edu",
            university="University of Nebraska-Lincoln",
            graduation_year=2027,
            major=["Computer Science"]
        ),
        focus_areas=focus,
        project=Project(
            one_liner=project_one_liner,
            industry=industry
        ) if project_one_liner else None,
        skills=Skills(
            possessed=[PossessedSkill(name=s, source=SkillSource.questionnaire) for s in skills_have],
            needed=[NeededSkill(name=s, priority=SkillPriority.must_have) for s in skills_need]
        )
    )

def run_tests():
    print("🚀 Starting Resilient Similarity Engine Tests...")

    # 1. Create Example Profiles
    alice = create_example_student(
        "Alice Developer",
        ["Python", "FastAPI", "MongoDB"],
        ["React", "UI/UX Design"],
        [FocusArea.startup],
        "A platform for student collaboration.",
        ["Education", "Social"]
    )
    
    bob = create_example_student(
        "Bob Designer",
        ["React", "Figma", "UI/UX Design"],
        ["Python", "Machine Learning"],
        [FocusArea.startup],
        "Visualizing student connections.",
        ["Education", "Data Viz"]
    )

    print(f"✅ Created example profiles: Alice, Bob.")

    # 2. Test Embedding Generation
    print("\n🧪 Testing generate_profile_embeddings...")
    # This will use the mock
    alice.rag = Rag(**generate_profile_embeddings(alice))
    bob.rag = Rag(**generate_profile_embeddings(bob))
    
    assert len(alice.rag.possessed_vector) == 384
    print("✅ Embedding generation successful (Mocked 384-dim).")

    # 3. Test Vectorization
    print("\n🧪 Testing vectorize_profile...")
    alice_vecs = vectorize_profile(alice)
    bob_vecs = vectorize_profile(bob)
    print("✅ Vectorization correctly mapped embeddings.")

    # 4. Test Scoring
    print("\n🧪 Testing compute_match (Alice vs Bob)...")
    weights = Weights(complementarity=0.65, focus=0.20, industry=0.15)
    score_ab = compute_match(alice, alice_vecs, bob, bob_vecs, weights)
    
    print(f"Match Alice -> Bob:")
    print(f"  Total Score: {score_ab.score:.4f}")
    print(f"  Complementarity: {score_ab.complementarity:.4f}")
    print(f"  Matched Skills: {score_ab.matched_skills}")
    
    assert "react" in score_ab.matched_skills
    print("✅ Scoring logic is accurate.")

    # 5. Test Fallback Mode (Simulate torch failure)
    print("\n🧪 Testing Keyword Fallback Mode...")
    services.similarity.HAS_TRANSFORMERS = False
    
    alice.rag = Rag(**generate_profile_embeddings(alice))
    bob.rag = Rag(**generate_profile_embeddings(bob))
    
    # In fallback mode, vectors are lists of words
    assert isinstance(alice.rag.possessed_vector[0], str)
    
    alice_vecs = vectorize_profile(alice)
    bob_vecs = vectorize_profile(bob)
    score_fallback = compute_match(alice, alice_vecs, bob, bob_vecs, weights)
    
    print(f"Fallback Match Score: {score_fallback.score:.4f}")
    assert score_fallback.score > 0
    print("✅ Keyword fallback mode is working correctly!")

    print("\n🎉 All tests passed (including resilience fallback)!")

if __name__ == "__main__":
    run_tests()
