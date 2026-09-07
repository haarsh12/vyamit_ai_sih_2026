from app.domain.customers import is_meaningful_customer_name


def test_customer_name_validation_accepts_spoken_names_in_supported_scripts() -> None:
    assert is_meaningful_customer_name("Rahul")
    assert is_meaningful_customer_name("  Ravi   Kumar ")
    assert is_meaningful_customer_name("श्रिकांत")


def test_customer_name_validation_rejects_empty_generic_and_numeric_values() -> None:
    for value in (None, "", " ", "Walk-in", "unknown", "no name", "12345", "--"):
        assert not is_meaningful_customer_name(value)
