from pathlib import Path


def test_video_generation_skill_uses_python3_command():
    skill_path = Path(__file__).resolve().parents[2] / "skills/public/video-generation/SKILL.md"
    content = skill_path.read_text()

    assert "python3 /mnt/skills/public/video-generation/scripts/generate.py" in content
