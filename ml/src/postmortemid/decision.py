from enum import StrEnum


class Decision(StrEnum):
    MATCH = "match"
    REVIEW = "review"
    NO_MATCH = "no_match"


def decide(score: float, tau_far1: float, tau_far01: float) -> Decision:
    """Three-band decision from the proposal (Section 3.2.3).

    tau_far01 is the stricter threshold (FAR 0.1%), so it must be at least tau_far1.
    """
    if tau_far01 < tau_far1:
        raise ValueError("tau_far01 must be >= tau_far1")
    if score >= tau_far01:
        return Decision.MATCH
    if score < tau_far1:
        return Decision.NO_MATCH
    return Decision.REVIEW
