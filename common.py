import sys
import shutil
import textwrap
import curses
import os

def clear():
 os.system('cls' if os.name == 'nt' else 'clear')

def get_console_width():
 columns, rows = shutil.get_terminal_size()
 return columns

def wrap(text, width=get_console_width()):
 wrapped_text = textwrap.wrap(text, width=width)
 for line in wrapped_text:
  print(line)
 print("")

def line():
 print("—" * get_console_width() + "\n")

def get_query():
 query = " ".join(sys.argv[1:]) if (len(sys.argv) > 1) else sys.stdin.read()
 heading(query)
 return(query)

def bold(str):
 return f"\033[1m{str}\033[0m"

def heading(str):
 clear()
 line()
 wrap(str)
 line()
