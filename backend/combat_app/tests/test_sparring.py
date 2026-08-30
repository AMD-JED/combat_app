"""
Tests for the v6 Sparring matching system:
  - manual request/accept flow (create, incoming/outgoing, respond)
  - automatic match suggestions based on 'combat' sport profile attributes
"""
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.sport import Sport


async def seed_combat_sport(db_session: AsyncSession) -> None:
    db_session.add(Sport(slug="combat", name="Combat Sports", is_active=True))
    await db_session.flush()


async def register_and_login(client: AsyncClient, email: str, username: str) -> str:
    await client.post("/api/v1/auth/register", json={
        "email": email,
        "username": username,
        "full_name": "Test Fighter",
        "password": "testpass123",
        "password_confirm": "testpass123",
    })
    resp = await client.post("/api/v1/auth/login", data={
        "username": email,
        "password": "testpass123",
    })
    return resp.json()["access_token"]


async def get_my_id(client: AsyncClient, token: str) -> int:
    resp = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    return resp.json()["id"]


async def set_combat_profile(
    client: AsyncClient, token: str, discipline: str, weight_class: str, belt_rank: str
) -> None:
    resp = await client.post(
        "/api/v1/sports/me/profiles",
        json={
            "sport_slug": "combat",
            "is_primary": True,
            "attributes": {
                "discipline": discipline,
                "weight_class": weight_class,
                "belt_rank": belt_rank,
            },
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 201, resp.text


@pytest.mark.asyncio
async def test_suggestions_empty_when_combat_sport_not_seeded(client: AsyncClient):
    """If the 'combat' Sport row doesn't exist at all yet, suggestions is
    just an empty list (nothing to match against) rather than an error."""
    token = await register_and_login(client, "nosport@test.com", "no_sport_fighter")
    resp = await client.get(
        "/api/v1/sparring/suggestions", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_suggestions_require_combat_profile(
    client: AsyncClient, db_session: AsyncSession
):
    """'combat' sport exists, but this user hasn't added a combat profile
    to themselves yet -> 400, since there's nothing to match on."""
    await seed_combat_sport(db_session)
    token = await register_and_login(client, "nomatch@test.com", "no_match_fighter")
    resp = await client.get(
        "/api/v1/sparring/suggestions", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_suggestions_match_on_discipline_weight_belt(
    client: AsyncClient, db_session: AsyncSession
):
    await seed_combat_sport(db_session)

    token_a = await register_and_login(client, "sparA@test.com", "spar_a")
    token_b = await register_and_login(client, "sparB@test.com", "spar_b")

    await set_combat_profile(client, token_a, "MMA", "Lightweight", "Blue Belt")
    await set_combat_profile(client, token_b, "MMA", "Lightweight", "Blue Belt")

    resp = await client.get(
        "/api/v1/sparring/suggestions", headers={"Authorization": f"Bearer {token_a}"}
    )
    assert resp.status_code == 200
    suggestions = resp.json()
    assert len(suggestions) == 1
    assert suggestions[0]["user"]["username"] == "spar_b"
    assert suggestions[0]["match_score"] == 3
    assert suggestions[0]["shared_weight_class"] == "Lightweight"
    assert suggestions[0]["shared_belt_rank"] == "Blue Belt"


@pytest.mark.asyncio
async def test_suggestions_exclude_different_discipline(
    client: AsyncClient, db_session: AsyncSession
):
    await seed_combat_sport(db_session)

    token_a = await register_and_login(client, "mmaFighter@test.com", "mma_fighter")
    token_b = await register_and_login(client, "boxer@test.com", "boxer_fighter")

    await set_combat_profile(client, token_a, "MMA", "Welterweight", "Black Belt")
    await set_combat_profile(client, token_b, "Boxing", "Welterweight", "Black Belt")

    resp = await client.get(
        "/api/v1/sparring/suggestions", headers={"Authorization": f"Bearer {token_a}"}
    )
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_cannot_request_self(client: AsyncClient):
    token = await register_and_login(client, "solo_spar@test.com", "solo_spar")
    my_id = await get_my_id(client, token)

    resp = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": my_id},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_full_request_accept_flow(client: AsyncClient):
    token_a = await register_and_login(client, "reqA@test.com", "req_a")
    token_b = await register_and_login(client, "reqB@test.com", "req_b")
    b_id = await get_my_id(client, token_b)

    # A requests B
    resp = await client.post(
        "/api/v1/sparring/requests",
        json={
            "recipient_id": b_id,
            "message": "Ready to roll this weekend?",
            "location": "Iron Gym, Algiers",
        },
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert resp.status_code == 201, resp.text
    request_id = resp.json()["id"]
    assert resp.json()["status"] == "pending"

    # Duplicate pending request blocked (either direction)
    dup = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": b_id},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert dup.status_code == 400

    # B sees it in incoming
    incoming = await client.get(
        "/api/v1/sparring/requests/incoming", headers={"Authorization": f"Bearer {token_b}"}
    )
    assert incoming.status_code == 200
    assert any(r["id"] == request_id for r in incoming.json())

    # A sees it in outgoing
    outgoing = await client.get(
        "/api/v1/sparring/requests/outgoing", headers={"Authorization": f"Bearer {token_a}"}
    )
    assert any(r["id"] == request_id for r in outgoing.json())

    # A (requester) cannot accept their own request
    forbidden = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "accept"},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert forbidden.status_code == 403

    # B accepts
    accept = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "accept"},
        headers={"Authorization": f"Bearer {token_b}"},
    )
    assert accept.status_code == 200
    assert accept.json()["status"] == "accepted"

    # Cannot accept again (already accepted)
    again = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "accept"},
        headers={"Authorization": f"Bearer {token_b}"},
    )
    assert again.status_code == 400

    # A (requester) cancels the accepted session
    cancel = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "cancel"},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert cancel.status_code == 200
    assert cancel.json()["status"] == "cancelled"

    # Now that it's cancelled (a terminal state), a brand new request
    # between the same two users is allowed again.
    new_request = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": b_id},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert new_request.status_code == 201


@pytest.mark.asyncio
async def test_duplicate_blocked_while_accepted_not_just_pending(client: AsyncClient):
    """A new request between the same two users must also be blocked
    while a prior one is 'accepted' (an upcoming session), not just while
    it's 'pending'."""
    token_a = await register_and_login(client, "activeA@test.com", "active_a")
    token_b = await register_and_login(client, "activeB@test.com", "active_b")
    b_id = await get_my_id(client, token_b)

    resp = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": b_id},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    request_id = resp.json()["id"]

    accept = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "accept"},
        headers={"Authorization": f"Bearer {token_b}"},
    )
    assert accept.json()["status"] == "accepted"

    # Either direction should be blocked while it's accepted.
    dup_same_direction = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": b_id},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert dup_same_direction.status_code == 400

    a_id = await get_my_id(client, token_a)
    dup_reverse_direction = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": a_id},
        headers={"Authorization": f"Bearer {token_b}"},
    )
    assert dup_reverse_direction.status_code == 400


@pytest.mark.asyncio
async def test_decline_flow_and_recipient_only_action(client: AsyncClient):
    token_a = await register_and_login(client, "declineA@test.com", "decline_a")
    token_b = await register_and_login(client, "declineB@test.com", "decline_b")
    b_id = await get_my_id(client, token_b)

    resp = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": b_id},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    request_id = resp.json()["id"]

    # Requester cannot decline their own request (only recipient can)
    forbidden = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "decline"},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert forbidden.status_code == 403

    decline = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "decline"},
        headers={"Authorization": f"Bearer {token_b}"},
    )
    assert decline.status_code == 200
    assert decline.json()["status"] == "declined"


@pytest.mark.asyncio
async def test_unrelated_user_cannot_respond(client: AsyncClient):
    token_a = await register_and_login(client, "outsiderA@test.com", "outsider_a")
    token_b = await register_and_login(client, "outsiderB@test.com", "outsider_b")
    token_c = await register_and_login(client, "outsiderC@test.com", "outsider_c")
    b_id = await get_my_id(client, token_b)

    resp = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": b_id},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    request_id = resp.json()["id"]

    forbidden = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "accept"},
        headers={"Authorization": f"Bearer {token_c}"},
    )
    assert forbidden.status_code == 403


@pytest.mark.asyncio
async def test_request_to_nonexistent_user(client: AsyncClient):
    token = await register_and_login(client, "ghostReq@test.com", "ghost_req")
    resp = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": 999999},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_request_linked_to_gym_and_open_mat(client: AsyncClient):
    """v7: sparring requests can optionally anchor to a real gym/open mat
    instead of (or alongside) free-text location."""
    owner_token = await register_and_login(client, "spargymowner@test.com", "spar_gym_owner")
    requester_token = await register_and_login(client, "spargymreq@test.com", "spar_gym_req")
    b_id = await get_my_id(client, owner_token)

    gym_resp = await client.post(
        "/api/v1/gyms/",
        json={"name": "Sparring Anchor Gym", "location": "Setif"},
        headers={"Authorization": f"Bearer {owner_token}"},
    )
    gym_id = gym_resp.json()["id"]

    open_mat_resp = await client.post(
        f"/api/v1/gyms/{gym_id}/open-mats",
        json={
            "title": "Anchor Open Mat",
            "is_recurring": True,
            "recurrence_day": "monday",
            "start_time": "17:00:00",
        },
        headers={"Authorization": f"Bearer {owner_token}"},
    )
    open_mat_id = open_mat_resp.json()["id"]

    resp = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": b_id, "gym_id": gym_id, "open_mat_id": open_mat_id},
        headers={"Authorization": f"Bearer {requester_token}"},
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["gym_id"] == gym_id
    assert resp.json()["open_mat_id"] == open_mat_id

    # Use fresh recipients below so the "duplicate active request" check
    # (tested separately in test_full_request_accept_flow) doesn't mask
    # what these two cases are actually meant to verify.
    recipient_c_token = await register_and_login(client, "spargymrecC@test.com", "spar_gym_rec_c")
    c_id = await get_my_id(client, recipient_c_token)

    # open_mat_id that doesn't belong to gym_id is rejected
    other_gym = await client.post(
        "/api/v1/gyms/",
        json={"name": "Other Gym", "location": "Setif"},
        headers={"Authorization": f"Bearer {owner_token}"},
    )
    mismatch = await client.post(
        "/api/v1/sparring/requests",
        json={
            "recipient_id": c_id,
            "gym_id": other_gym.json()["id"],
            "open_mat_id": open_mat_id,
        },
        headers={"Authorization": f"Bearer {requester_token}"},
    )
    assert mismatch.status_code == 400

    recipient_d_token = await register_and_login(client, "spargymrecD@test.com", "spar_gym_rec_d")
    d_id = await get_my_id(client, recipient_d_token)

    # nonexistent gym_id is rejected
    bad_gym = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": d_id, "gym_id": 999999},
        headers={"Authorization": f"Bearer {requester_token}"},
    )
    assert bad_gym.status_code == 404
