import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import react from "@astrojs/react";
import remarkHeadingID from "remark-heading-id";
import remarkGemoji from "remark-gemoji";
import AstroPWA from "@vite-pwa/astro";
import manifest from "./webmanifest.json";

// https://astro.build/config
export default defineConfig({
  site: "https://swamp.linwood.dev",
  markdown: {
    remarkPlugins: [remarkHeadingID, remarkGemoji],
  },
  integrations: [
    starlight({
      title: "Linwood Swamp",
      customCss: [
        // Relative path to your custom CSS file
        "./src/styles/custom.css",
      ],
      logo: {
        src: "./public/favicon.svg",
      },
      favicon: "./favicon.ico",
      social: {
        mastodon: "https://floss.social/@linwood",
        matrix: "https://linwood.dev/matrix",
        discord: "https://linwood.dev/discord",
        github: "https://github.com/LinwoodDev/Swamp",
      },
      components: {
        SocialIcons: "./src/components/CustomSocialIcons.astro",
        Head: "./src/components/Head.astro",
        Footer: "./src/components/Footer.astro",
        ContentPanel: "./src/components/ContentPanel.astro",
      },
      sidebar: [
        {
          label: "Guides",
          items: [
            // Each item here is one entry in the navigation menu.
            { label: "Example Guide", slug: "guides/example" },
          ],
        },
        {
          label: "Reference",
          autogenerate: { directory: "reference" },
        },
      ],
    }),
    AstroPWA({
      workbox: {
        skipWaiting: true,
        clientsClaim: true,
        navigateFallback: "/404",
        ignoreURLParametersMatching: [/./],
        globPatterns: [
          "**/*.{html,js,css,png,svg,json,ttf,pf_fragment,pf_index,pf_meta,pagefind,wasm}",
        ],
      },
      experimental: {
        directoryAndTrailingSlashHandler: true,
      },
      registerType: "autoUpdate",
      manifest,
    }),
    react(),
  ],
});
