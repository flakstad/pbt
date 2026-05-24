package pbt

Rng :: struct {
	state: u64,
}

rng_init :: proc(seed: u64) -> Rng {
	state := seed
	if state == 0 {
		state = 0x9e37_79b9_7f4a_7c15
	}

	return {state = state}
}

rng_next :: proc(rng: ^Rng) -> u64 {
	x := rng.state
	x ~= x >> 12
	x ~= x << 25
	x ~= x >> 27
	rng.state = x
	return x * 0x2545_f491_4f6c_dd1d
}

rng_bounded :: proc(rng: ^Rng, upper_exclusive: u64) -> u64 {
	if upper_exclusive <= 1 {
		return 0
	}

	return rng_next(rng) % upper_exclusive
}
