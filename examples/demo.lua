return unit. Demo {
  const. Welcome [i32] (2026),
  const. One [i32] (1),
  const. Zero [i32] (0),

  struct. Pair {
    head [i32],
    tail [i32],
  },

  union. Result {
    ok { value [i32] },
    err { code [i32] },
    none,
  },

  handle. SessionRef {
    invalid = 0,
  },

  expr_frag. inc { x [i32] } [i32] (x + 1),
  expr_frag. abs_i32 { x [i32] } [i32] (select (x :lt (0), 0 - x, x)),

  fn. add { a [i32], b [i32] } [i32] {
    ret (a + b),
  },

  fn. abs_value { x [i32] } [i32] {
    ret (select (x :lt (0), 0 - x, x)),
  },

  region. hit_or_miss
    { x [i32] }
    {
      hit { pos [i32] },
      miss,
    }
    {
      entry. start {} {
        when (x :gt (0)) {
          jump. hit { pos = x },
        },

        jump. miss {},
      },
    },

  fn. region_demo { x [i32] } [i32] {
    entry. start {} {
      emit. hit_or_miss { x } {
        hit = done,
        miss = zero,
      },
    },

    block. done { pos [i32] } {
      ret (pos),
    },

    block. zero {} {
      ret (0),
    },
  },

  fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds(xs, n), readonly(xs) },

    entry. start {} {
      jump. loop { i = 0, acc = 0 },
    },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop {
        i = i + 1,
        acc = acc + xs[i],
      },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },
}
