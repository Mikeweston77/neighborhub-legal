#!/usr/bin/env python3
"""
Convert Markdown legal documents to HTML for GitHub Pages
"""

import re

def markdown_to_html(markdown_text, title):
    """Convert markdown to HTML with styling"""
    
    # Convert headers
    html = markdown_text
    html = re.sub(r'^# (.+)$', r'<h1>\1</h1>', html, flags=re.MULTILINE)
    html = re.sub(r'^## (.+)$', r'<h2>\1</h2>', html, flags=re.MULTILINE)
    html = re.sub(r'^### (.+)$', r'<h3>\1</h3>', html, flags=re.MULTILINE)
    html = re.sub(r'^#### (.+)$', r'<h4>\1</h4>', html, flags=re.MULTILINE)
    
    # Convert bold
    html = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', html)
    
    # Convert italic
    html = re.sub(r'\*(.+?)\*', r'<em>\1</em>', html)
    
    # Convert links
    html = re.sub(r'\[(.+?)\]\((.+?)\)', r'<a href="\2">\1</a>', html)
    
    # Convert lists
    lines = html.split('\n')
    in_list = False
    result = []
    
    for line in lines:
        if line.strip().startswith('- '):
            if not in_list:
                result.append('<ul>')
                in_list = True
            item = line.strip()[2:]
            result.append(f'<li>{item}</li>')
        else:
            if in_list:
                result.append('</ul>')
                in_list = False
            if line.strip() and not line.startswith('<h'):
                result.append(f'<p>{line}</p>')
            else:
                result.append(line)
    
    if in_list:
        result.append('</ul>')
    
    html = '\n'.join(result)
    
    # Wrap in full HTML document
    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title} - NeighborHub</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.8;
            color: #333;
            background: #f5f5f7;
            padding: 20px;
        }}
        
        .container {{
            max-width: 900px;
            margin: 0 auto;
            background: white;
            padding: 60px;
            border-radius: 12px;
            box-shadow: 0 2px 20px rgba(0, 0, 0, 0.1);
        }}
        
        .back-link {{
            display: inline-block;
            margin-bottom: 30px;
            color: #667eea;
            text-decoration: none;
            font-weight: 600;
        }}
        
        .back-link:hover {{
            text-decoration: underline;
        }}
        
        h1 {{
            color: #1d1d1f;
            font-size: 2.5em;
            margin-bottom: 10px;
            padding-bottom: 20px;
            border-bottom: 3px solid #667eea;
        }}
        
        h2 {{
            color: #667eea;
            font-size: 1.8em;
            margin-top: 40px;
            margin-bottom: 15px;
        }}
        
        h3 {{
            color: #764ba2;
            font-size: 1.4em;
            margin-top: 30px;
            margin-bottom: 10px;
        }}
        
        h4 {{
            color: #555;
            font-size: 1.2em;
            margin-top: 20px;
            margin-bottom: 10px;
        }}
        
        p {{
            margin-bottom: 15px;
            color: #555;
            font-size: 1.05em;
        }}
        
        ul {{
            margin-left: 30px;
            margin-bottom: 20px;
        }}
        
        li {{
            margin-bottom: 8px;
            color: #555;
        }}
        
        strong {{
            color: #333;
            font-weight: 600;
        }}
        
        a {{
            color: #667eea;
            text-decoration: none;
        }}
        
        a:hover {{
            text-decoration: underline;
        }}
        
        .footer {{
            margin-top: 60px;
            padding-top: 30px;
            border-top: 1px solid #ddd;
            text-align: center;
            color: #888;
        }}
        
        @media (max-width: 768px) {{
            .container {{
                padding: 30px 20px;
            }}
            
            h1 {{
                font-size: 2em;
            }}
            
            h2 {{
                font-size: 1.5em;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <a href="index.html" class="back-link">← Back to Home</a>
        
{html}
        
        <div class="footer">
            <p><a href="index.html">Back to Home</a> | <a href="mailto:support@neighborhub.app">Contact Us</a></p>
        </div>
    </div>
</body>
</html>
"""
    
    return full_html


def main():
    # Convert Privacy Policy
    with open('PRIVACY_POLICY.md', 'r') as f:
        privacy_md = f.read()
    
    privacy_html = markdown_to_html(privacy_md, 'Privacy Policy')
    
    with open('docs/privacy.html', 'w') as f:
        f.write(privacy_html)
    
    print("✅ Generated docs/privacy.html")
    
    # Convert Terms of Service
    with open('TERMS_OF_SERVICE.md', 'r') as f:
        terms_md = f.read()
    
    terms_html = markdown_to_html(terms_md, 'Terms of Service')
    
    with open('docs/terms.html', 'w') as f:
        f.write(terms_html)
    
    print("✅ Generated docs/terms.html")
    print("\n📁 GitHub Pages files ready in ./docs/")
    print("\nNext steps:")
    print("1. Create a new GitHub repository")
    print("2. Push this code to GitHub")
    print("3. Enable GitHub Pages in repo settings (use /docs folder)")
    print("4. Your URLs will be:")
    print("   https://YOUR-USERNAME.github.io/REPO-NAME/privacy.html")
    print("   https://YOUR-USERNAME.github.io/REPO-NAME/terms.html")


if __name__ == '__main__':
    main()
