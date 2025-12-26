# GitHub Pages Setup Guide for NeighborHub Legal Documents

## 📋 Quick Setup Steps

### 1. Create GitHub Repository

1. Go to https://github.com/new
2. **Repository name**: `neighborhub-legal` (or any name you prefer)
3. **Visibility**: Public (required for free GitHub Pages)
4. **Don't** initialize with README, .gitignore, or license
5. Click **Create repository**

### 2. Push Your Code to GitHub

Run these commands in your terminal:

```bash
cd "/Users/mike/Desktop/Waterfall 3 V1.06"

# Initialize git repository
git init

# Add the docs folder
git add docs/

# Commit the files
git commit -m "Add Privacy Policy and Terms of Service for GitHub Pages"

# Add your GitHub repository as remote (replace YOUR-USERNAME and REPO-NAME)
git remote add origin https://github.com/YOUR-USERNAME/REPO-NAME.git

# Push to GitHub
git branch -M main
git push -u origin main
```

### 3. Enable GitHub Pages

1. Go to your repository on GitHub
2. Click **Settings** (top right)
3. Click **Pages** in the left sidebar
4. Under **Source**, select:
   - Branch: `main`
   - Folder: `/docs`
5. Click **Save**
6. Wait 1-2 minutes for deployment

### 4. Get Your URLs

Your legal documents will be available at:

```
https://YOUR-USERNAME.github.io/REPO-NAME/
https://YOUR-USERNAME.github.io/REPO-NAME/privacy.html
https://YOUR-USERNAME.github.io/REPO-NAME/terms.html
```

**Example** (if username is `john` and repo is `neighborhub-legal`):
- https://john.github.io/neighborhub-legal/privacy.html
- https://john.github.io/neighborhub-legal/terms.html

### 5. Add URLs to App Store Connect

When submitting to App Store:
1. **Privacy Policy URL**: `https://YOUR-USERNAME.github.io/REPO-NAME/privacy.html`
2. **Support URL**: `https://YOUR-USERNAME.github.io/REPO-NAME/`

---

## ✅ What's Been Created

```
docs/
├── index.html        # Landing page with links to both documents
├── privacy.html      # Privacy Policy (HTML)
└── terms.html        # Terms of Service (HTML)
```

## 🎨 Features

- ✅ Fully responsive design (mobile-friendly)
- ✅ Clean, professional styling
- ✅ Easy navigation between documents
- ✅ Matches NeighborHub branding colors
- ✅ No dependencies (pure HTML/CSS)

## 🔄 Alternative: Using GitHub Gist (Simpler)

If you want an even simpler solution:

1. Go to https://gist.github.com
2. Create a new gist with `privacy_policy.md`
3. Paste your PRIVACY_POLICY.md content
4. Click "Create public gist"
5. Copy the URL (e.g., https://gist.github.com/username/abc123)

**Note**: GitHub Pages with custom HTML looks more professional for App Store submission.

## 🆘 Troubleshooting

**Page not loading after enabling GitHub Pages?**
- Wait 2-3 minutes for initial deployment
- Check Settings → Pages for deployment status
- Ensure repository is public

**404 error on privacy.html?**
- Verify files are in `/docs` folder
- Check that GitHub Pages source is set to `/docs`
- Clear browser cache

**Need to update content?**
- Edit PRIVACY_POLICY.md or TERMS_OF_SERVICE.md
- Run `python3 convert_to_html.py`
- Commit and push changes: `git add docs/ && git commit -m "Update legal docs" && git push`

## 📱 Next Steps

1. ✅ Files created and ready
2. ⏳ Push to GitHub
3. ⏳ Enable GitHub Pages
4. ⏳ Copy URLs to App Store Connect
5. ⏳ Test URLs in browser

---

**Need help?** Check https://docs.github.com/en/pages/getting-started-with-github-pages
