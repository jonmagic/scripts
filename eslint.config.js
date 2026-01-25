import js from "@eslint/js"
import tseslint from "typescript-eslint"
import prettier from "eslint-config-prettier"

export default [
  {
    ignores: [
      "**/dist/**",
      "**/dist/**/*.test.*",
      "**/*.d.ts",
      "**/out/**",
      "**/node_modules/**",
      "**/.vscode-test/**"
    ]
  },

  js.configs.recommended,

  ...tseslint.configs.recommendedTypeChecked.map((config) => ({
    ...config,
    files: ["**/*.{ts,tsx}"],
    ignores: [
      "**/*.test.ts",
      "**/*.test.tsx",
      "**/*.spec.ts",
      "**/*.spec.tsx"
    ]
  })),

  {
    // Type-aware rules only for TS/TSX.
    files: ["**/*.{ts,tsx}"],
    ignores: [
      "**/*.test.ts",
      "**/*.test.tsx",
      "**/*.spec.ts",
      "**/*.spec.tsx"
    ],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
        // Non-test TS files should be in a project; fail closed.
      }
    },
    rules: {
      // Style (we intentionally keep a light footprint here)
      semi: ["error", "never"],

      // Safe-ish defaults
      eqeqeq: ["error", "always"],
      curly: ["error", "all"],
      "no-var": "error",
      "prefer-const": ["error", { destructuring: "all" }],
      "object-shorthand": ["error", "always"],

      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": [
        "error",
        {
          // JSX/React event handlers are commonly async; banning that is more pain than value.
          checksVoidReturn: { attributes: false }
        }
      ],
      "@typescript-eslint/consistent-type-imports": [
        "error",
        { prefer: "type-imports" }
      ]
    }
  },

  {
    // Light JS linting (no type-aware parsing needed for config/build scripts).
    files: ["**/*.{js,mjs,cjs}"],
    languageOptions: {
      globals: {
        console: "readonly",
        process: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        module: "readonly",
        require: "readonly"
      }
    },
    rules: {
      semi: ["error", "never"]
    }
  },

  {
    // TS test files: lint them, but don't require them to be part of a type-aware project.
    files: [
      "**/*.test.ts",
      "**/*.test.tsx",
      "**/*.spec.ts",
      "**/*.spec.tsx"
    ],
    languageOptions: {
      parserOptions: {
        projectService: false
      }
    }
  },

  ...tseslint.configs.recommended.map((config) => ({
    ...config,
    files: [
      "**/*.test.ts",
      "**/*.test.tsx",
      "**/*.spec.ts",
      "**/*.spec.tsx"
    ]
  })),

  prettier
]
