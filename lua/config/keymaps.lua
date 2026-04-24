-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Ctrl+Backspace to delete word in insert and command mode
vim.keymap.set("i", "<C-BS>", "<C-w>", { desc = "Delete word backward" })
vim.keymap.set("i", "<C-H>", "<C-w>", { desc = "Delete word backward" })
vim.keymap.set("c", "<C-BS>", "<C-w>", { desc = "Delete word backward" })
vim.keymap.set("c", "<C-H>", "<C-w>", { desc = "Delete word backward" })

-- Markdown preview in a vsplit
vim.keymap.set("n", "<leader>mp", function()
  if vim.bo.filetype ~= "markdown" then
    vim.notify("Not a markdown file", vim.log.levels.WARN)
    return
  end

  local src_buf = vim.api.nvim_get_current_buf()

  -- create preview buffer
  local prev_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, vim.api.nvim_buf_get_lines(src_buf, 0, -1, false))
  vim.bo[prev_buf].filetype = "markdown"
  vim.bo[prev_buf].modifiable = false
  vim.bo[prev_buf].bufhidden = "wipe"

  -- open vsplit right
  vim.cmd("botright vsplit")
  vim.api.nvim_win_set_buf(0, prev_buf)

  -- sync source -> preview
  local group = vim.api.nvim_create_augroup("MdPreview_" .. prev_buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = src_buf,
    callback = function()
      if not vim.api.nvim_buf_is_valid(prev_buf) then
        pcall(vim.api.nvim_del_augroup_by_id, group)
        return
      end
      vim.bo[prev_buf].modifiable = true
      vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, vim.api.nvim_buf_get_lines(src_buf, 0, -1, false))
      vim.bo[prev_buf].modifiable = false
    end,
  })

  -- go back to source
  vim.cmd("wincmd p")
end, { desc = "Markdown split preview" })

-- Close terminal split and wipe its buffer
vim.keymap.set("n", "<leader>rt", function()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end, { desc = "Close all terminal splits" })

-- MIPT C++ homework: switch task, configure, build & run tests
-- Usage: :Task result   or   :Task calculator
local mipt_root = "/home/ivanc/MIPT/CPP_HW/cpp_gerunov.iv_25"

vim.api.nvim_create_user_command("Task", function(opts)
  local task = opts.args
  if task == "" then
    vim.notify("Usage: :Task <task_name>", vim.log.levels.ERROR)
    return
  end

  local testing_dir = mipt_root .. "/testing_repo/" .. task
  local cmake_file = testing_dir .. "/CMakeLists.txt"
  local build_dir = mipt_root .. "/build"

  -- check that the task exists
  if vim.fn.isdirectory(testing_dir) == 0 then
    vim.notify("Task not found: " .. testing_dir, vim.log.levels.ERROR)
    return
  end

  -- ensure include_directories line exists in CMakeLists.txt
  local include_line = "include_directories(../../" .. task .. ")"
  local content = vim.fn.readfile(cmake_file)
  local has_include = false
  for _, line in ipairs(content) do
    if line:find(include_line, 1, true) then
      has_include = true
      break
    end
  end
  if not has_include then
    -- insert before enable_testing()
    local new_content = {}
    for _, line in ipairs(content) do
      if line:find("enable_testing", 1, true) then
        table.insert(new_content, include_line)
      end
      table.insert(new_content, line)
    end
    vim.fn.writefile(new_content, cmake_file)
    vim.notify("Added " .. include_line .. " to CMakeLists.txt")
  end

  -- find the source header to run clang-tidy on
  local header = mipt_root .. "/" .. task .. "/" .. task .. ".hpp"

  -- configure + build + run + clang-tidy
  local cmd = string.format(
    "cmake -S %s -B %s && cmake --build %s -j$(nproc) && %s/%s && echo '\\n=== clang-tidy ===' && clang-tidy -p %s --config-file=%s/.clang-tidy %s",
    vim.fn.shellescape(testing_dir),
    vim.fn.shellescape(build_dir),
    vim.fn.shellescape(build_dir),
    vim.fn.shellescape(build_dir),
    task,
    vim.fn.shellescape(build_dir),
    vim.fn.shellescape(testing_dir),
    vim.fn.shellescape(header)
  )
  vim.cmd("split | terminal " .. cmd)
end, {
  nargs = 1,
  complete = function()
    -- autocomplete with available task directories
    local dirs = vim.fn.globpath(mipt_root .. "/testing_repo", "*", false, true)
    local tasks = {}
    for _, d in ipairs(dirs) do
      if vim.fn.isdirectory(d) == 1 then
        table.insert(tasks, vim.fn.fnamemodify(d, ":t"))
      end
    end
    return tasks
  end,
})

-- Build & run current task again (rerun last :Task)
vim.keymap.set("n", "<leader>rb", function()
  local build_dir = mipt_root .. "/build"
  local cmd = string.format("cmake --build %s -j$(nproc) && %s/*", vim.fn.shellescape(build_dir), build_dir)
  vim.cmd("split | terminal " .. cmd)
end, { desc = "Rebuild & run MIPT task" })

-- MIPT Python homework
-- Usage: :PyTask part4_oop
-- Runs: format -> pytest -> mypy -> flake8 -> ruff check
local py_root = "/home/ivanc/MIPT/Python_HW/mipt_python_homeworks_2026"

vim.api.nvim_create_user_command("PyTask", function(opts)
  local part = opts.args
  if part == "" then
    vim.notify("Usage: :PyTask <part_name>  (e.g. part4_oop)", vim.log.levels.ERROR)
    return
  end

  local part_dir = py_root .. "/" .. part
  if vim.fn.isdirectory(part_dir) == 0 then
    vim.notify("Part not found: " .. part_dir, vim.log.levels.ERROR)
    return
  end

  -- find hw*.py in the part directory
  local hw_files = vim.fn.glob(part_dir .. "/hw*.py", false, true)
  if #hw_files == 0 then
    vim.notify("No hw*.py found in " .. part_dir, vim.log.levels.ERROR)
    return
  end
  local hw_file = hw_files[1]
  local tests_dir = part_dir .. "/tests"

  local cmd = string.format(
    "cd %s && uv run ruff format %s && uv run pytest %s && uv run mypy %s && uv run flake8 %s && uv run ruff check %s",
    vim.fn.shellescape(py_root),
    vim.fn.shellescape(hw_file),
    vim.fn.shellescape(tests_dir),
    vim.fn.shellescape(hw_file),
    vim.fn.shellescape(hw_file),
    vim.fn.shellescape(hw_file)
  )
  vim.cmd("split | terminal " .. cmd)
end, {
  nargs = 1,
  complete = function()
    local dirs = vim.fn.glob(py_root .. "/part*", false, true)
    local parts = {}
    for _, d in ipairs(dirs) do
      if vim.fn.isdirectory(d) == 1 then
        table.insert(parts, vim.fn.fnamemodify(d, ":t"))
      end
    end
    return parts
  end,
})

-- Quick rerun: just pytest for current Python part
vim.keymap.set("n", "<leader>rp", function()
  -- detect part from current file path
  local file = vim.fn.expand("%:p")
  local part = file:match(py_root .. "/([^/]+)/")
  if not part then
    vim.notify("Not inside a Python HW part directory", vim.log.levels.WARN)
    return
  end
  local part_dir = py_root .. "/" .. part
  local tests_dir = part_dir .. "/tests"
  local cmd = string.format("cd %s && uv run pytest %s", vim.fn.shellescape(py_root), vim.fn.shellescape(tests_dir))
  vim.cmd("split | terminal " .. cmd)
end, { desc = "Run pytest for current Python HW part" })

-- Format C/C++ with makebeautiful
vim.keymap.set("n", "<leader>rf", function()
  local file = vim.fn.expand("%:p")
  vim.cmd("silent !makebeautiful " .. vim.fn.shellescape(file))
  vim.cmd("edit!")
  vim.notify("Formatted: " .. vim.fn.expand("%:t"))
end, { desc = "Format C/C++ with makebeautiful" })

-- Competitive programming: compile & run tests
vim.keymap.set("n", "<leader>rc", function()
  local file = vim.fn.expand("%:p")
  vim.cmd("split | terminal ~/.local/bin/cp-test " .. vim.fn.shellescape(file))
end, { desc = "Run CP tests for current file" })

-- Run current file with <leader>rx
vim.keymap.set("n", "<leader>rx", function()
  local ft = vim.bo.filetype
  local file = vim.fn.expand("%:p")
  local cmd

  if ft == "cpp" or ft == "c" then
    local out = vim.fn.expand("%:p:r")
    local compiler = ft == "c" and "clang" or "clang++"
    cmd = compiler .. " -o " .. vim.fn.shellescape(out) .. " " .. vim.fn.shellescape(file) .. " && " .. vim.fn.shellescape(out)
  elseif ft == "python" then
    cmd = "python3 " .. vim.fn.shellescape(file)
  else
    vim.notify("No run command for filetype: " .. ft, vim.log.levels.WARN)
    return
  end

  vim.cmd("split | terminal " .. cmd)
end, { desc = "Run current file" })
