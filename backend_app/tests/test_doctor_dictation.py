from app.domain.doctor_prescriptions import format_dictation


def test_doctor_dictation_returns_an_editable_draft_not_a_persisted_record() -> None:
    result = format_dictation(
        "Patient name is Raju age 45 male diagnosis viral fever prescribe Paracetamol 500mg twice daily after food for 5 days"
    )
    draft = result["draft"]
    assert result["type"] == "PRESCRIPTION_DRAFT"
    assert draft["patient"]["name"] == "Raju"
    assert draft["patient"]["age"] == 45
    assert draft["medications"][0]["name"] == "Paracetamol"
    assert draft["medications"][0]["dose"] == "500mg"


def test_doctor_dictation_does_not_invent_a_medication() -> None:
    result = format_dictation("Patient name is Sita age 30 diagnosis headache")
    assert result["draft"]["medications"] == []
