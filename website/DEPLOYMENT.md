# Runalyst Website Deployment Guide (`runalyst.ca`)

The promotional landing page in `website/` is pre-configured for instant zero-configuration deployment to either **GitHub Pages** or **Cloudflare Pages**.

---

## 1. GitHub Pages (Automated Workflow)

A production-ready GitHub Actions workflow is included at [deploy-pages.yml](file:///.github/workflows/deploy-pages.yml).

### Repository Setting
1. On GitHub, navigate to **Settings** &rarr; **Pages**.
2. Under **Build and deployment** &rarr; **Source**, select **GitHub Actions**.

### DNS Configuration for `runalyst.ca`
Add the following DNS records at your domain registrar:

| Type | Host / Name | Target / Value | TTL |
| :--- | :--- | :--- | :--- |
| **A** | `@` | `185.199.108.153` | Auto / 300 |
| **A** | `@` | `185.199.109.153` | Auto / 300 |
| **A** | `@` | `185.199.110.153` | Auto / 300 |
| **A** | `@` | `185.199.111.153` | Auto / 300 |
| **CNAME** | `www` | `<your-github-username>.github.io` | Auto / 300 |

*Note:* `website/CNAME` already specifies `runalyst.ca`, and `website/.nojekyll` prevents Jekyll processing.

---

## 2. Cloudflare Pages (Zero Config)

### Dashboard Setup
1. In Cloudflare Dashboard, go to **Workers & Pages** &rarr; **Create application** &rarr; **Pages** &rarr; **Connect to Git**.
2. Select the `runalyst` repository.
3. Configure build settings:
   - **Framework preset**: None
   - **Build command**: *(leave blank)*
   - **Build output directory**: `website`
4. Click **Save and Deploy**.

### Custom Domain
1. In your Cloudflare Pages project, go to **Custom Domains** &rarr; **Set up a domain**.
2. Enter `runalyst.ca` and `www.runalyst.ca`.
3. Cloudflare automatically manages the DNS and provisions a free SSL certificate.

*Note:* `website/_headers` is already pre-configured with Cloudflare caching headers (1 year immutable cache for video and image assets).
