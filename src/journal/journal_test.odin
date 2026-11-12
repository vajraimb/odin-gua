package journal

import "core:testing"

@(test)
test_similarity :: proc(t: ^testing.T) {
	testing.expect_value(t, similarity("要不要接这个项目？", "要不要接 这个项目"), 1.0)
	testing.expect(t, similarity("下周的谈判能成吗", "下周的谈判能成吗？会顺利吗") >= 0.7)
	testing.expect(t, similarity("要不要换工作", "今年要不要搬家") < 0.7)
	testing.expect(t, similarity("Should I move?", "should i move") == 1.0)
	testing.expect_value(t, similarity("", "x"), 0.0)
}

@(test)
test_dates :: proc(t: ^testing.T) {
	testing.expect(t, valid_date("2026-11-12"))
	testing.expect(t, !valid_date("2026-13-01"))
	testing.expect(t, !valid_date("2026/11/12"))
	testing.expect(t, date_after_days(14) > today())
}
