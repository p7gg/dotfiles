# Keep user-local binaries ahead of system binaries, with ~/.local/bin before
# the OpenCode installer directory and the Go bin directory, and avoid duplicate
# PATH entries.
set -l preferred $HOME/.local/bin $HOME/.opencode/bin $HOME/.go/bin
set -l new_path

for dir in $preferred
    if not contains $dir $new_path
        set -a new_path $dir
    end
end

for dir in $PATH
    if not contains $dir $new_path
        set -a new_path $dir
    end
end

set -gx PATH $new_path
