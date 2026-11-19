'use strict';

// Clipboard-only enhancement. This page never sends prompts or invokes a model.
document.addEventListener('click', async (event) => {
  const button = event.target.closest('button[data-copy]');
  if (!button) return;
  const target = button.dataset.copy;
  const status = document.getElementById('api-copy-status');
  const base = document.getElementById('public-api-base');
  const model = document.getElementById('public-api-model');
  const key = document.getElementById('public-api-key');
  const field = target === 'all' ? null : document.getElementById(target);
  if (!status || !base || !model || !key || (target !== 'all' && !field)) return;
  const value = target === 'all'
    ? `API 协议: OpenAI Chat Completions\nBase URL: ${base.value}\nModel ID: ${model.value}\nAPI Key: ${key.value}\nmax_tokens: 16384`
    : field.value;
  try {
    await navigator.clipboard.writeText(value);
    status.textContent = target === 'all' ? '全部配置已复制，可粘贴到你的客户端。' : '已复制。';
  } catch {
    if (field) {
      field.focus();
      field.select();
    }
    status.textContent = '浏览器未允许自动复制，请选中配置后手动复制。';
  }
});
