import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // HEHA-inspired warm palette
        cream: "#fffaf2",
        sand: "#f8efe2",
        peach: "#ffe1c2",
        orange: {
          DEFAULT: "#ff8a24",
          soft: "#fff1df",
          bright: "#ff9f3f",
          deep: "#e85d2b",
        },
        ink: "#191715",
        muted: "#746d66",
        line: "#efe3d5",
        moss: {
          DEFAULT: "#67845f",
          dark: "#174432",
          soft: "#edf6ef",
        },
      },
      fontFamily: {
        display: ["var(--font-syne)", "Syne", "system-ui", "sans-serif"],
        sans: ["var(--font-dmsans)", "DM Sans", "system-ui", "sans-serif"],
      },
      borderRadius: {
        xl: "1rem",
        "2xl": "1.5rem",
        "3xl": "2rem",
      },
      boxShadow: {
        soft: "0 20px 48px rgba(47, 36, 22, .10)",
        card: "0 18px 42px rgba(47, 36, 22, .12)",
        glow: "0 12px 30px rgba(255, 138, 36, .28)",
      },
      backgroundImage: {
        "warm-radial":
          "radial-gradient(circle at 50% 28%, rgba(255,138,36,.10), transparent 30%), linear-gradient(180deg, #ffffff 0%, #fffaf2 100%)",
      },
    },
  },
  plugins: [],
};

export default config;
