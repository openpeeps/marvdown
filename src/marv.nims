--mm:arc
--threads:on
# --define:toktokdebug
when defined release:
  --define:danger
  --opt:speed
  --passC:"-flto"
  --checks:off