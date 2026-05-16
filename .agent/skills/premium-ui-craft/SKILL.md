# Skill: Premium UI Craft

This skill focuses on creating luxury-grade, high-performance web interfaces that go beyond basic functionality to provide a "wow" factor through sophisticated design and micro-interactions.

## 🎯 When to use
- When building front-end components, landing pages, or dashboards.
- When the user requests a "premium" or "high-quality" feel.
- When implementing brand-heavy interfaces.

## 🛠️ Craftsmanship Standards

### 1. Aesthetic Refinement
- **Generous Spacing**: Use sophisticated white space to create a "luxury" feel.
- **Typography**: Implement clear hierarchy and high-quality font scales.
- **Glassmorphism**: Use backdrop filters and subtle borders for a modern look.
- **Theme Toggle**: Mandatory light/dark/system theme support with smooth transitions.

### 2. Interactive Excellence
- **Micro-interactions**: Subtle feedback on hover, click, and transition.
- **Smooth Animations**: Maintain 60fps for all visual transitions.
- **Magnetic Effects**: Elements that attract or react to the cursor.
- **Innovation**: Use Three.js or advanced CSS (organic shapes, custom gradients) where appropriate.

### 3. Performance & Quality
- **Lighthouse Goals**: Target >90 for Performance and Accessibility.
- **Load Times**: Aim for under 1.5s visual completion.
- **Responsive Mastery**: Perfect layout across all device sizes.

## 📝 Code Patterns

### Glass Morphism (CSS)
```css
.luxury-glass {
    background: rgba(255, 255, 255, 0.05);
    backdrop-filter: blur(20px) saturate(180%);
    border: 1px solid rgba(255, 255, 255, 0.1);
    box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37);
}
```

### Smooth Transitions (Tailwind/CSS)
```html
<button class="transition-all duration-300 ease-out hover:scale-105 hover:shadow-xl">
    Premium Action
</button>
```

## 💡 Communication
- "Enhanced with glass morphism and magnetic hover effects to create a premium feel."
- "Optimized animations for 60fps smooth experience across all devices."
