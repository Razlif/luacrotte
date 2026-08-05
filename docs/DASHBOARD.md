# Live roadmap dashboard

`roadmap-dashboard.html` reads `TODO.md` and `ROADMAP.md` every time it loads.
Serve the project root once:

```cmd
py -m http.server 8765
```

Then open http://localhost:8765/docs/roadmap-dashboard.html . Edit either
Markdown file and refresh the page to see the update.
