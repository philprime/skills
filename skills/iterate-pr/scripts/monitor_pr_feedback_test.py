#!/usr/bin/env python3

import contextlib
import io
import sys
import unittest
from unittest.mock import patch

import monitor_pr_feedback


class MonitorPRFeedbackTest(unittest.TestCase):
    def test_registered_checks_are_terminal_only_without_actionable_pending_work(self) -> None:
        cases = [
            ({'summary': {'total': 0, 'actionable_pending': 0}}, False),
            ({'summary': {'total': 10, 'actionable_pending': 1}}, False),
            ({'summary': {'total': 10, 'actionable_pending': 0}}, True),
            ({'error': 'GitHub unavailable'}, False),
            (None, False),
        ]

        for checks, expected in cases:
            with self.subTest(checks=checks):
                self.assertEqual(
                    monitor_pr_feedback.registered_checks_are_terminal(checks),
                    expected,
                )

    def test_exits_when_registered_checks_are_terminal_and_feedback_is_clear(self) -> None:
        feedback = {
            'summary': {'high': 0, 'medium': 0, 'low': 0},
            'feedback': {'high': [], 'medium': [], 'low': []},
        }
        checks = {
            'summary': {
                'total': 10,
                'failed': 0,
                'actionable_pending': 0,
                'human_gate_pending': 0,
            }
        }
        output = io.StringIO()

        with (
            patch.object(monitor_pr_feedback, 'fetch_feedback', return_value=feedback),
            patch.object(monitor_pr_feedback, 'fetch_checks', return_value=checks),
            patch.object(sys, 'argv', ['monitor_pr_feedback.py', '--pr', '123']),
            contextlib.redirect_stdout(output),
        ):
            result = monitor_pr_feedback.main()

        self.assertEqual(result, 0)
        self.assertTrue(output.getvalue().startswith('NO_ACTIONABLE_FEEDBACK\n'))


if __name__ == '__main__':
    unittest.main()
