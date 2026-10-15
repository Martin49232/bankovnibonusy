#!/usr/bin/env bash
set -e

echo "Spoustim generovani webu bankovnibonusy.cz (data.json + referrals.json)..."

if ! command -v python3 &> /dev/null; then
  echo "Chyba: python3 neni nainstalovan."
  exit 1
fi

mkdir -p banky blog
rm -f blog/mbank.html banky/index.html

python3 - << 'EOF'
import json
import os

with open("data.json", "r", encoding="utf-8") as f:
    data = json.load(f)

referrals = {}
if os.path.exists("referrals.json"):
    with open("referrals.json", "r", encoding="utf-8") as rf:
        referrals = json.load(rf)

campaigns = [c for c in data.get("campaigns", []) if c.get("active")]
for c in campaigns:
    ref_info = referrals.get(c["id"], {})
    if isinstance(ref_info, dict):
        if ref_info.get("url"):
            c["affiliateUrl"] = ref_info["url"]
        c["promoCode"] = ref_info.get("promoCode", "")
    elif isinstance(ref_info, str) and ref_info:
        c["affiliateUrl"] = ref_info
        c["promoCode"] = ""

guides = data.get("guides", [])
faqs = data.get("faqs", [])
expired = data.get("expiredCampaigns", [])
history = data.get("bonusHistory", {})
last_updated = data.get("lastUpdated", "15. 10. 2026")
total_bonus = data.get("totalPossibleBonus", "26 200 Kč")

def render_logo(b):
    if b.get("imageWebp") and b.get("imagePng"):
        return f'''<picture class="bank-logo-pic">
          <source srcset="{b['imageWebp']}" type="image/webp">
          <img src="{b['imagePng']}" alt="{b['name']}" class="bank-logo" width="56" height="56" loading="lazy">
        </picture>'''
    short = b["name"].split(" ")[0]
    return f'<div class="bank-logo-fallback" style="background:{b["brandColor"]};color:{b["brandTextColor"]};">{short}</div>'

def render_bank_card(b):
    reqs = "".join([f"<li>{r}</li>" for r in b.get("requirements", [])])
    promo_html = f'<div class="promo-code-badge">Kód do žádosti: {b["promoCode"]}</div>' if b.get("promoCode") else ""
    return f'''<article class="bank-card">
      <div class="card-header">
        {render_logo(b)}
        <div>
          <h3><a href="/banky/{b['slugBank']}" style="color:inherit;">{b["name"]}</a></h3>
          <p class="account-type">{b["accountName"]}</p>
        </div>
      </div>
      <div class="bonus-box">
        <div class="bonus-row-validity">
          <span>Platnost akce</span>
          <strong>{b["validUntil"]}</strong>
        </div>
        <div class="bonus-row-main">
          <span class="bonus-label">Výše bonusu</span>
          <strong class="bonus-value">{b["bonusText"]}</strong>
        </div>
      </div>
      <div class="conditions-title">Podmínky pro získání</div>
      <ul class="req-list">{reqs}</ul>
      {promo_html}
      <div class="card-actions" style="margin-top:auto;padding-top:14px;">
        <a href="{b["affiliateUrl"]}" target="_blank" rel="noopener" class="btn btn-primary">Získat bonus</a>
        <a href="/banky/{b["slugBank"]}" class="btn btn-secondary">Podrobnosti</a>
      </div>
      <div class="card-links">
        <a href="{b["termsUrl"]}" target="_blank" rel="noopener">Oficiální podmínky banky</a>
        <a href="/banky/{b["slugBank"]}">Postup krok za krokem</a>
      </div>
    </article>'''

def render_bonus_chart(history_data):
    periods = history_data.get("periods", [])
    series_list = history_data.get("series", [])
    if not periods or not series_list:
        return ""

    width = 960
    height = 420
    pad_left = 78
    pad_right = 36
    pad_top = 28
    pad_bottom = 48
    plot_w = width - pad_left - pad_right
    plot_h = height - pad_top - pad_bottom
    max_val = 6000

    def get_x(idx):
        if len(periods) <= 1:
            return pad_left
        return round(pad_left + (idx / (len(periods) - 1)) * plot_w, 1)

    def get_y(val):
        return round(pad_top + plot_h - (min(val, max_val) / max_val) * plot_h, 1)

    grid_lines = []
    for y_val in [0, 1000, 2000, 3000, 4000, 5000, 6000]:
        y_pos = get_y(y_val)
        label = f"{y_val:,} Kč".replace(",", " ")
        grid_lines.append(
            f'<line x1="{pad_left}" y1="{y_pos}" x2="{width - pad_right}" y2="{y_pos}" stroke="#e5e7eb" stroke-dasharray="4 4" stroke-width="1"/>'
            f'<text x="{pad_left - 12}" y="{y_pos + 5}" text-anchor="end" fill="#6b7280" font-size="13" font-family="Inter, sans-serif">{label}</text>'
        )

    x_labels = []
    for i, p in enumerate(periods):
        x_pos = get_x(i)
        x_labels.append(
            f'<line x1="{x_pos}" y1="{pad_top}" x2="{x_pos}" y2="{height - pad_bottom}" stroke="#f3f4f6" stroke-width="1"/>'
            f'<text x="{x_pos}" y="{height - 14}" text-anchor="middle" fill="#374151" font-weight="600" font-size="13" font-family="Inter, sans-serif">{p}</text>'
        )

    svg_series = []
    legend_buttons = []
    for s in series_list:
        s_id = s["id"]
        s_name = s["name"]
        s_color = s["color"]
        vals = s["values"]

        pts = [f"{get_x(i)},{get_y(v)}" for i, v in enumerate(vals)]
        polyline = f'<polyline class="chart-line" data-series="{s_id}" points="{" ".join(pts)}" stroke="{s_color}"/>'

        circles = []
        for i, v in enumerate(vals):
            cx = get_x(i)
            cy = get_y(v)
            val_fmt = f"{v:,} Kč".replace(",", " ")
            circles.append(
                f'<circle class="chart-point" data-series="{s_id}" cx="{cx}" cy="{cy}" r="5" fill="{s_color}" stroke="#ffffff" stroke-width="2" '
                f'data-bank="{s_name}" data-year="{periods[i]}" data-val="{val_fmt}"/>'
            )

        svg_series.append(f'<g class="chart-group" data-series="{s_id}">{polyline}{"".join(circles)}</g>')
        legend_buttons.append(
            f'<button type="button" class="legend-btn" data-toggle-series="{s_id}">'
            f'<span class="legend-dot" style="background:{s_color};"></span>{s_name}'
            f'</button>'
        )

    chart_js = '''
    <script>
    (function() {
      const buttons = document.querySelectorAll('[data-toggle-series]');
      const tooltip = document.getElementById('chart-tooltip');

      buttons.forEach(btn => {
        btn.addEventListener('click', () => {
          btn.classList.toggle('inactive');
          const id = btn.getAttribute('data-toggle-series');
          const group = document.querySelector('.chart-group[data-series="' + id + '"]');
          if (group) {
            group.style.opacity = btn.classList.contains('inactive') ? '0.08' : '1';
            group.style.pointerEvents = btn.classList.contains('inactive') ? 'none' : 'auto';
          }
        });
      });

      document.querySelectorAll('.chart-point').forEach(pt => {
        pt.addEventListener('mouseenter', () => {
          const bank = pt.getAttribute('data-bank');
          const year = pt.getAttribute('data-year');
          const val = pt.getAttribute('data-val');
          tooltip.innerHTML = '<strong>' + bank + ' (' + year + ')</strong><br>Maximální bonus: ' + val;
          tooltip.style.opacity = '1';
        });
        pt.addEventListener('mousemove', (e) => {
          tooltip.style.left = (e.clientX + 14) + 'px';
          tooltip.style.top = (e.clientY - 36) + 'px';
        });
        pt.addEventListener('mouseleave', () => {
          tooltip.style.opacity = '0';
        });
      });
    })();
    </script>
    '''

    return f'''
    <div class="chart-card">
      <div class="chart-legend" aria-label="Filtr bank v grafu">
        {"".join(legend_buttons)}
      </div>
      <div class="chart-svg-wrapper">
        <svg class="bonus-chart-svg" viewBox="0 0 {width} {height}" role="img" aria-label="Graf vývoje bankovních bonusů v letech 2019 až 2026">
          {"".join(grid_lines)}
          {"".join(x_labels)}
          {"".join(svg_series)}
        </svg>
      </div>
      <div id="chart-tooltip" class="chart-tooltip"></div>
      <div class="chart-footer-note">
        <span>Kliknutím na název banky v legendě lze křivku v grafu skrýt nebo zobrazit. Najetím myší na bod zobrazíte přesnou částku.</span>
        <a href="/expirovane-kampane.html">Zobrazit kompletní archiv 30+ kampaní</a>
      </div>
    </div>
    {chart_js}
    '''

def wrap_layout(title, description, canonical_path, active_nav, body_html, schema_json=""):
    nav_home = 'class="active"' if active_nav == "home" else ""
    nav_blog = 'class="active"' if active_nav == "blog" else ""
    nav_exp = 'class="active"' if active_nav == "exp" else ""
    schema_tag = f'<script type="application/ld+json">{schema_json}</script>' if schema_json else ""
    canonical_url = f"https://bankovnibonusy.cz{canonical_path}"

    return f'''<!DOCTYPE html>
<html lang="cs">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title}</title>
  <meta name="description" content="{description}">
  <link rel="canonical" href="{canonical_url}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="{canonical_url}">
  <meta property="og:title" content="{title}">
  <meta property="og:description" content="{description}">
  <meta property="og:image" content="https://bankovnibonusy.cz/images/bonusOG.jpg">
  <link rel="stylesheet" href="/style.css">
  {schema_tag}
</head>
<body>
  <header class="site-header">
    <div class="container header-inner">
      <a href="/" class="logo">Bankovní<span>Bonusy.cz</span></a>
      <nav class="main-nav" aria-label="Hlavní navigace">
        <a href="/" {nav_home}>Přehled bonusů</a>
        <a href="/blog/" {nav_blog}>Návody a články</a>
        <a href="/expirovane-kampane.html" {nav_exp}>Archiv akcí</a>
      </nav>
    </div>
  </header>

  <main class="container">
    {body_html}
  </main>

  <footer class="site-footer">
    <div class="container footer-inner">
      <div>
        <strong>BankovníBonusy.cz</strong>
        <p style="margin-top:4px;color:#94a3b8;">Nezávislé srovnání finančních odměn za založení běžného účtu a doporučení v ČR.</p>
      </div>
      <div class="footer-links">
        <a href="/">Přehled bonusů</a>
        <a href="/blog/">Návody a články</a>
        <a href="/expirovane-kampane.html">Archiv kampaní</a>
      </div>
    </div>
  </footer>
</body>
</html>'''

# 1. Generování index.html
cards_html = "".join([render_bank_card(b) for b in campaigns])
chart_html = render_bonus_chart(history)

faq_html = "".join([f'''<div class="faq-item">
  <h3>{q['question']}</h3>
  <p>{q['answer']}</p>
</div>''' for q in faqs])

faq_schema = json.dumps({
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [{
    "@type": "Question",
    "name": q["question"],
    "acceptedAnswer": {"@type": "Answer", "text": q["answer"]}
  } for q in faqs]
}, ensure_ascii=False)

index_body = f'''
<section class="hero">
  <span class="hero-meta">Aktualizováno {last_updated}</span>
  <h1>Srovnání bankovních bonusů za založení a doporučení účtu</h1>
  <p>Přehled aktuálních finančních odměn u českých bank v celkové výši až {total_bonus}. Všechny uvedené účty mají založení i vedení zdarma. Pro aktivaci bonusu přejděte na žádost přes tlačítko u vybrané banky.</p>
</section>

<section aria-label="Aktuální bankovní bonusy">
  <div class="cards-grid">{cards_html}</div>
</section>

<section aria-label="Vývoj bankovních bonusů v čase">
  <div class="section-header">
    <h2>Vývoj výše bankovních bonusů v ČR (2019–2026)</h2>
    <p>Historické srovnání maximálních uvítacích odměn jednotlivých bank. Barva každé křivky odpovídá příslušné bance.</p>
  </div>
  {chart_html}
</section>

<section class="faq-section">
  <div class="section-header">
    <h2>Často kladené dotazy</h2>
  </div>
  {faq_html}
</section>
'''

with open("index.html", "w", encoding="utf-8") as f:
    f.write(wrap_layout(
        f"Bankovní Bonusy 2026 | Srovnání odměn za založení účtu (až {total_bonus})",
        "Přehledné srovnání bankovních bonusů za založení běžného účtu v ČR. Získejte odměnu u Air Bank, Raiffeisenbank, České spořitelny, mBank, KB či ČSOB.",
        "/", "home", index_body, faq_schema
    ))

# 2. Generování detailů bank (/banky/*.html) a recenzí (/blog/banka-*.html)
top_sidebar_links = "".join([
    f'<li><a href="/banky/{x["slugBank"]}"><strong>{x["name"]}</strong> – {x["bonusText"]}</a></li>'
    for x in campaigns[:4]
])

for b in campaigns:
    reqs = "".join([f"<li>{r}</li>" for r in b["requirements"]])
    steps = "".join([f"<li>{s}</li>" for s in b["steps"]])
    ref_link = f'<p style="margin-top:8px;"><a href="{b["referralTermsUrl"]}" target="_blank" rel="noopener">Podmínky programu doporučení / dětských účtů</a></p>' if b.get("referralTermsUrl") else ""
    promo_detail = f'<p style="margin-top:6px;"><strong>Promo kód do žádosti:</strong> <code>{b["promoCode"]}</code></p>' if b.get("promoCode") else ""

    for page_type in ["bank", "blog"]:
        is_blog = (page_type == "blog")
        slug = f"/blog/{b['slugBlog']}" if is_blog else f"/banky/{b['slugBank']}"
        file_path = os.path.join("blog", b["slugBlog"]) if is_blog else os.path.join("banky", b["slugBank"])
        h1_title = b["blogTitle"] if is_blog else f"{b['name']} – Bonus {b['bonusText']}"
        page_title = f"{h1_title} | Bankovní Bonusy"
        meta_desc = b["blogPerex"] if is_blog else b["shortDescription"]
        breadcrumb_parent = '<a href="/blog/">Návody a články</a>' if is_blog else '<a href="/">Přehled bonusů</a>'

        detail_body = f'''
        <nav class="breadcrumbs">
          <a href="/">Domů</a> / 
          {breadcrumb_parent} / 
          <span>{b["name"]}</span>
        </nav>
        <div class="detail-hero">
          <div class="detail-header">
            {render_logo(b)}
            <div>
              <span class="hero-meta" style="margin-bottom:4px;">Platnost akce: {b["validUntil"]}</span>
              <h1>{h1_title}</h1>
            </div>
          </div>
          <div class="detail-cta-bar">
            <div>
              <strong style="font-size:1.15rem;color:#111827;">Výše bonusu: {b["bonusText"]}</strong>
              <p style="color:#4b5563;margin-top:4px;">Pro aktivaci odměny otevřete žádost přes akční tlačítko vpravo.</p>
              {promo_detail}
            </div>
            <div class="cta-buttons">
              <a href="{b["affiliateUrl"]}" target="_blank" rel="noopener" class="btn btn-primary">Získat bonus u {b["name"]}</a>
              <a href="{b["termsUrl"]}" target="_blank" rel="noopener" class="btn btn-secondary">Oficiální podmínky (PDF/Web)</a>
            </div>
          </div>
        </div>

        <div class="detail-grid">
          <article class="detail-main">
            <h2>Podrobné informace a hodnocení nabídky</h2>
            <p>{b["shortDescription"]}</p>
            {b["blogContent"]}
            <h2>Postup krok za krokem: Jak získat bonus</h2>
            <ol>{steps}</ol>
            <div class="internal-callout">
              <strong>Související návod:</strong> Přečtěte si také náš přehled <a href="/blog/jak-ziskat-bonus.html">Jak zkombinovat bankovní bonusy na maximum</a> nebo článek <a href="/blog/bankovni-bonusy-za-doporuceni-mgm.html">Jak fungují programy doporučení</a>.
            </div>
          </article>
          <aside class="detail-sidebar">
            <div class="sidebar-box">
              <h3>Základní podmínky</h3>
              <ul class="req-list">{reqs}</ul>
              <hr style="margin:20px 0;border:0;border-top:1px solid #e5e7eb;">
              <p style="font-size:0.95rem;color:#374151;"><strong>Doplňkové akce:</strong><br>{b["specialBonus"]}</p>
              <p style="margin-top:12px;"><a href="{b["termsUrl"]}" target="_blank" rel="noopener">Oficiální podmínky akce</a></p>
              {ref_link}
              <a href="{b["affiliateUrl"]}" target="_blank" rel="noopener" class="btn btn-primary" style="width:100%;margin-top:18px;">Získat bonus u {b["name"]}</a>
              <hr style="margin:24px 0;border:0;border-top:1px solid #e5e7eb;">
              <h3>Další vybrané bonusy</h3>
              <ul class="req-list" style="margin-bottom:0;">{top_sidebar_links}</ul>
            </div>
          </aside>
        </div>
        '''
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(wrap_layout(page_title, meta_desc, slug, "blog" if is_blog else "home", detail_body))

# 3. Generování tematických průvodců (/blog/*.html)
for g in guides:
    file_path = os.path.join("blog", g["slug"])
    takeaways = "".join([f"<li>{t}</li>" for t in g.get("keyTakeaways", [])])
    related_guides = "".join([
        f'<li><a href="/blog/{rg["slug"]}">{rg["title"]}</a></li>'
        for rg in guides if rg["slug"] != g["slug"]
    ][:5])

    article_schema = json.dumps({
      "@context": "https://schema.org",
      "@type": "Article",
      "headline": g["title"],
      "description": g["metaDescription"],
      "datePublished": "2026-10-15",
      "dateModified": "2026-10-15",
      "author": {"@type": "Organization", "name": "BankovníBonusy.cz"}
    }, ensure_ascii=False)

    guide_body = f'''
    <nav class="breadcrumbs"><a href="/">Domů</a> / <a href="/blog/">Návody a články</a> / <span>{g["category"]}</span></nav>
    <div class="detail-grid">
      <article class="detail-main">
        <div class="blog-card-meta">
          <span>{g["category"]}</span>
          <span>{g["readingTime"]}</span>
        </div>
        <h1 style="font-size:2rem;color:#0f2942;line-height:1.25;margin-bottom:16px;">{g["title"]}</h1>
        <p style="font-size:1.15rem;color:#374151;margin-bottom:24px;">{g["perex"]}</p>
        <div class="bonus-box" style="margin-bottom:28px;">
          <span class="bonus-label" style="display:block;margin-bottom:6px;">Hlavní body článku</span>
          <ul class="req-list" style="margin-bottom:0;">{takeaways}</ul>
        </div>
        {g["content"]}
        <hr style="margin:32px 0;border:0;border-top:1px solid #e5e7eb;">
        <h3>Další praktické návody</h3>
        <ul>{related_guides}</ul>
      </article>
      <aside class="detail-sidebar">
        <div class="sidebar-box">
          <h3>Nejvyšší bankovní bonusy</h3>
          <p style="font-size:0.95rem;color:#4b5563;margin-bottom:16px;">Aktuálně nejvýhodnější odměny za založení a doporučení účtu:</p>
          <ul class="req-list">{top_sidebar_links}</ul>
          <a href="/" class="btn btn-primary" style="width:100%;margin-top:8px;">Zobrazit přehled bonusů</a>
        </div>
      </aside>
    </div>
    '''
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(wrap_layout(f"{g['title']} | Bankovní Bonusy", g["metaDescription"], f"/blog/{g['slug']}", "blog", guide_body, article_schema))

# 4. Generování /blog/index.html
guides_cards = "".join([f'''<article class="blog-card">
  <div class="blog-card-meta"><span>{g["category"]}</span><span>{g["readingTime"]}</span></div>
  <h3><a href="/blog/{g["slug"]}">{g["title"]}</a></h3>
  <p class="card-desc">{g["perex"]}</p>
  <a href="/blog/{g["slug"]}" class="btn btn-secondary">Přečíst článek</a>
</article>''' for g in guides])

bank_blog_cards = "".join([f'''<article class="blog-card">
  <div class="blog-card-meta"><span>{b["name"]}</span><strong>Odměna {b["bonusText"]}</strong></div>
  <h3><a href="/blog/{b["slugBlog"]}">{b["blogTitle"]}</a></h3>
  <p class="card-desc">{b["blogPerex"]}</p>
  <div class="card-actions">
    <a href="/blog/{b["slugBlog"]}" class="btn btn-secondary">Přečíst recenzi</a>
    <a href="{b["termsUrl"]}" target="_blank" rel="noopener" class="btn btn-secondary">Podmínky</a>
  </div>
</article>''' for b in campaigns])

blog_index_body = f'''
<nav class="breadcrumbs"><a href="/">Domů</a> / <span>Návody a články</span></nav>
<section class="hero" style="padding-top:16px;">
  <h1>Návody, strategie a podrobné recenze bankovních bonusů</h1>
  <p>Praktické informace o tom, jak splnit podmínky obratu a plateb kartou, jak fungují programy doporučení a které účty jsou zcela bez poplatků.</p>
</section>
<div class="section-header">
  <h2>Tematické návody a tipy</h2>
</div>
<div class="cards-grid">{guides_cards}</div>
<div class="section-header">
  <h2>Podrobné rozbory jednotlivých bank</h2>
</div>
<div class="cards-grid">{bank_blog_cards}</div>
'''
with open("blog/index.html", "w", encoding="utf-8") as f:
    f.write(wrap_layout(
        "Návody a články o bankovních bonusech | Bankovní Bonusy",
        "Praktický průvodce bankovními bonusy v ČR. Jak získat odměnu za založení účtu, jak fungují bonusy za doporučení, dětské účty a OSVČ účty.",
        "/blog/", "blog", blog_index_body
    ))

# 5. Generování /expirovane-kampane.html
exp_items = "".join([f'''<div class="expired-item">
  <div>
    <h3 style="font-size:1.15rem;color:#0f2942;margin-bottom:4px;">{e["name"]}</h3>
    <p style="color:#4b5563;font-size:0.98rem;">{e["note"]}</p>
  </div>
  <div style="text-align:right;min-width:160px;">
    <strong style="font-size:1.2rem;color:#6b7280;">{e["bonusText"]}</strong><br>
    <span style="color:#6b7280;font-size:0.88rem;">Ukončeno: {e["ended"]}</span>
  </div>
</div>''' for e in expired])

exp_body = f'''
<nav class="breadcrumbs"><a href="/">Domů</a> / <span>Archiv ukončených akcí</span></nav>
<section class="hero" style="padding-top:16px;">
  <h1>Archiv a vývoj bankovních bonusů v ČR (2019–2026)</h1>
  <p>Kompletní historický přehled dřívějších kampaní českých bank a graf vývoje odměn za založení účtu v čase.</p>
</section>
<section aria-label="Graf vývoje bonusů">
  {chart_html}
</section>
<section style="margin-bottom:64px;">
  <div class="section-header">
    <h2>Seznam ukončených kampaní ({len(expired)} archivních akcí)</h2>
  </div>
  {exp_items}
</section>
'''
with open("expirovane-kampane.html", "w", encoding="utf-8") as f:
    f.write(wrap_layout(
        "Archiv a historie bankovních bonusů v ČR (2019–2026) | Bankovní Bonusy",
        "Kompletní přehled historických a expirovaných kampaní českých bank za založení účtu včetně grafu vývoje odměn od roku 2019.",
        "/expirovane-kampane.html", "exp", exp_body
    ))

# 6. Generování sitemap.xml
sitemap_urls = [
    ("https://bankovnibonusy.cz/", "1.0"),
    ("https://bankovnibonusy.cz/blog/", "0.9"),
    ("https://bankovnibonusy.cz/expirovane-kampane.html", "0.7"),
]
for g in guides:
    sitemap_urls.append((f"https://bankovnibonusy.cz/blog/{g['slug']}", "0.9"))
for b in campaigns:
    sitemap_urls.append((f"https://bankovnibonusy.cz/banky/{b['slugBank']}", "0.8"))
    sitemap_urls.append((f"https://bankovnibonusy.cz/blog/{b['slugBlog']}", "0.8"))

sitemap_xml = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
for url, prio in sitemap_urls:
    sitemap_xml += f"  <url><loc>{url}</loc><lastmod>2026-10-15</lastmod><priority>{prio}</priority></url>\n"
sitemap_xml += "</urlset>\n"

with open("sitemap.xml", "w", encoding="utf-8") as f:
    f.write(sitemap_xml)

print("Generovani vcetne propisovani odkazu z referrals.json uspesne dokonceno.")
EOF