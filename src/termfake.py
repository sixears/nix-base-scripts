import argparse
import fcntl
import sys
import termios

parser = argparse.ArgumentParser()
parser.add_argument('--tty', type=argparse.FileType('w'),
                    # default=os.ttyname(sys.stdout.fileno()),
                    default=sys.stdout,
                    help='device to use for the tty')

group = parser.add_mutually_exclusive_group()
group.add_argument('-n', action='store_true',
                   help='prevent sending a trailing newline character')
group.add_argument('--stdin', action='store_true',
                   help='read input from stdin')

group = parser.add_argument_group()
group.add_argument('cmd', nargs='?',
                   help='command to run (required if not using --stdin)')
group.add_argument('args', nargs='*',
                   help='arguments to command')
args = parser.parse_args()

if args.stdin:
    data = sys.stdin.read()
else:
    data = ' '.join([args.cmd] + args.args)

# tty = os.ttyname(args.tty.fileno())
# print(tty)
for c in data:
    fcntl.ioctl(args.tty, termios.TIOCSTI, c)
if not args.n and data[-1][-1] != '\n':
    fcntl.ioctl(args.tty, termios.TIOCSTI, '\n')

# -- that's all, folks! -------------------------------------------------------

# I hate the 4-level indent, but python/nix rules require it :-(
# Local Variables:
# mode: python
# python-indent-offset: 4
# End:

