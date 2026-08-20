from app.core.categories import stored_category, validate_category


def test_category_aliases_preserve_frontend_compatibility() -> None:
    assert stored_category("medical") == "Pharmacy"
    assert stored_category("prescription") == "Doctor Prescription"
    assert validate_category("fast food") == "Fast Food"


def test_unknown_category_is_rejected() -> None:
    try:
        validate_category("Not a valid category")
    except ValueError as error:
        assert "Unsupported shop category" in str(error)
    else:
        raise AssertionError("unknown category should not be accepted")
