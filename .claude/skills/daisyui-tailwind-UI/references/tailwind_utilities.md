# Essential Tailwind CSS Utilities

Quick reference for the most commonly used Tailwind utility classes when building UI with DaisyUI.

## Layout

### Display
```html
block inline inline-block flex inline-flex grid inline-grid
hidden
```

### Flexbox
```html
<!-- Direction -->
flex-row flex-row-reverse flex-col flex-col-reverse

<!-- Wrap -->
flex-wrap flex-wrap-reverse flex-nowrap

<!-- Justify Content -->
justify-start justify-end justify-center justify-between justify-around justify-evenly

<!-- Align Items -->
items-start items-end items-center items-baseline items-stretch

<!-- Align Self -->
self-auto self-start self-end self-center self-stretch

<!-- Flex Grow/Shrink -->
flex-1 flex-auto flex-initial flex-none
grow grow-0 shrink shrink-0

<!-- Gap -->
gap-0 gap-1 gap-2 gap-3 gap-4 gap-5 gap-6 gap-8 gap-10 gap-12
gap-x-4 gap-y-4
```

### Grid
```html
<!-- Grid Template Columns -->
grid-cols-1 grid-cols-2 grid-cols-3 grid-cols-4 grid-cols-5 grid-cols-6
grid-cols-12

<!-- Grid Column Span -->
col-span-1 col-span-2 col-span-3 col-span-full

<!-- Grid Template Rows -->
grid-rows-1 grid-rows-2 grid-rows-3

<!-- Grid Row Span -->
row-span-1 row-span-2 row-span-3 row-span-full

<!-- Gap -->
gap-4 gap-x-4 gap-y-4
```

### Container
```html
container mx-auto
```

### Position
```html
static fixed absolute relative sticky

<!-- Positioning -->
top-0 right-0 bottom-0 left-0
inset-0 inset-x-0 inset-y-0
```

### Z-Index
```html
z-0 z-10 z-20 z-30 z-40 z-50
```

## Spacing

### Padding
```html
<!-- All sides -->
p-0 p-1 p-2 p-3 p-4 p-5 p-6 p-8 p-10 p-12 p-16 p-20 p-24

<!-- Horizontal/Vertical -->
px-4 py-4

<!-- Individual sides -->
pt-4 pr-4 pb-4 pl-4
```

### Margin
```html
<!-- All sides -->
m-0 m-1 m-2 m-3 m-4 m-5 m-6 m-8 m-10 m-12 m-16 m-20 m-24
m-auto

<!-- Horizontal/Vertical -->
mx-4 my-4 mx-auto

<!-- Individual sides -->
mt-4 mr-4 mb-4 ml-4

<!-- Negative margins -->
-m-4 -mt-4 -mr-4 -mb-4 -ml-4
```

### Space Between
```html
space-x-0 space-x-1 space-x-2 space-x-4 space-x-8
space-y-0 space-y-1 space-y-2 space-y-4 space-y-8
```

## Sizing

### Width
```html
<!-- Fixed -->
w-0 w-1 w-2 w-4 w-6 w-8 w-10 w-12 w-16 w-20 w-24 w-32 w-40 w-48 w-56 w-64

<!-- Fractional -->
w-1/2 w-1/3 w-2/3 w-1/4 w-3/4
w-1/5 w-2/5 w-3/5 w-4/5
w-1/6 w-2/6 w-3/6 w-4/6 w-5/6

<!-- Percentage -->
w-full w-screen

<!-- Auto -->
w-auto

<!-- Min/Max -->
min-w-0 min-w-full
max-w-xs max-w-sm max-w-md max-w-lg max-w-xl max-w-2xl
max-w-screen-sm max-w-screen-md max-w-screen-lg max-w-screen-xl
```

### Height
```html
<!-- Fixed -->
h-0 h-1 h-2 h-4 h-6 h-8 h-10 h-12 h-16 h-20 h-24 h-32 h-40 h-48 h-56 h-64

<!-- Percentage -->
h-full h-screen

<!-- Auto -->
h-auto

<!-- Min/Max -->
min-h-0 min-h-full min-h-screen
max-h-full max-h-screen
```

## Typography

### Font Family
```html
font-sans font-serif font-mono
```

### Font Size
```html
text-xs text-sm text-base text-lg text-xl
text-2xl text-3xl text-4xl text-5xl text-6xl
```

### Font Weight
```html
font-thin font-extralight font-light font-normal
font-medium font-semibold font-bold font-extrabold font-black
```

### Text Alignment
```html
text-left text-center text-right text-justify
```

### Text Color
```html
<!-- With DaisyUI semantic colors -->
text-primary text-secondary text-accent
text-neutral text-base-content
text-info text-success text-warning text-error

<!-- Opacity -->
text-primary/50 text-primary/70 text-primary/90

<!-- Standard colors -->
text-black text-white
text-gray-100 text-gray-200 ... text-gray-900
```

### Text Transform
```html
uppercase lowercase capitalize normal-case
```

### Text Decoration
```html
underline line-through no-underline
```

### Line Height
```html
leading-none leading-tight leading-snug leading-normal
leading-relaxed leading-loose
```

### Letter Spacing
```html
tracking-tighter tracking-tight tracking-normal
tracking-wide tracking-wider tracking-widest
```

### Text Overflow
```html
truncate overflow-ellipsis overflow-clip
```

### Whitespace
```html
whitespace-normal whitespace-nowrap whitespace-pre whitespace-pre-line
```

## Colors

### Background Color
```html
<!-- With DaisyUI semantic colors -->
bg-primary bg-secondary bg-accent
bg-neutral bg-base-100 bg-base-200 bg-base-300
bg-info bg-success bg-warning bg-error

<!-- Opacity -->
bg-primary/50 bg-primary/70 bg-primary/90

<!-- Standard colors -->
bg-transparent bg-black bg-white
bg-gray-50 bg-gray-100 ... bg-gray-900
```

### Border Color
```html
border-primary border-secondary border-accent
border-neutral border-base-content
border-gray-200 border-gray-300
```

### Opacity
```html
opacity-0 opacity-25 opacity-50 opacity-75 opacity-100
```

## Borders

### Border Width
```html
border border-0 border-2 border-4 border-8
border-t border-r border-b border-l
border-x border-y
```

### Border Radius
```html
rounded-none rounded-sm rounded rounded-md rounded-lg rounded-xl
rounded-2xl rounded-3xl rounded-full

<!-- Individual corners -->
rounded-t rounded-r rounded-b rounded-l
rounded-tl rounded-tr rounded-br rounded-bl
```

### Border Style
```html
border-solid border-dashed border-dotted border-double border-none
```

## Effects

### Box Shadow
```html
shadow-sm shadow shadow-md shadow-lg shadow-xl shadow-2xl shadow-none
```

### Opacity
```html
opacity-0 opacity-25 opacity-50 opacity-75 opacity-100
```

### Cursor
```html
cursor-auto cursor-default cursor-pointer cursor-wait
cursor-text cursor-move cursor-not-allowed
```

## Transitions & Animations

### Transition
```html
transition transition-none transition-all
transition-colors transition-opacity transition-shadow transition-transform
```

### Duration
```html
duration-75 duration-100 duration-150 duration-200 duration-300
duration-500 duration-700 duration-1000
```

### Timing Function
```html
ease-linear ease-in ease-out ease-in-out
```

### Transform
```html
transform transform-gpu transform-none

<!-- Scale -->
scale-0 scale-50 scale-75 scale-90 scale-95 scale-100 scale-105 scale-110 scale-125 scale-150

<!-- Rotate -->
rotate-0 rotate-45 rotate-90 rotate-180 -rotate-45 -rotate-90 -rotate-180

<!-- Translate -->
translate-x-0 translate-y-0
translate-x-1 translate-x-2 translate-x-4
-translate-x-1 -translate-y-1
```

## Responsive Design

### Breakpoint Prefixes
```html
<!-- Apply at specific breakpoints -->
sm:  /* 640px and up */
md:  /* 768px and up */
lg:  /* 1024px and up */
xl:  /* 1280px and up */
2xl: /* 1536px and up */
```

### Common Responsive Patterns
```html
<!-- Responsive grid -->
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4">

<!-- Responsive text -->
<h1 class="text-2xl md:text-4xl lg:text-6xl">

<!-- Responsive spacing -->
<div class="p-4 md:p-6 lg:p-8">

<!-- Responsive display -->
<div class="hidden lg:block">
<div class="block lg:hidden">

<!-- Responsive width -->
<div class="w-full md:w-1/2 lg:w-1/3">
```

## Interactivity

### Hover, Focus, Active States
```html
<!-- Hover -->
hover:bg-primary hover:text-white hover:shadow-lg

<!-- Focus -->
focus:outline-none focus:ring-2 focus:ring-primary

<!-- Active -->
active:bg-primary-dark

<!-- Disabled -->
disabled:opacity-50 disabled:cursor-not-allowed
```

### Common Interactive Patterns
```html
<!-- Interactive button -->
<button class="btn hover:shadow-xl transition-shadow duration-200">

<!-- Interactive card -->
<div class="card hover:shadow-2xl transition-all duration-300 hover:-translate-y-1">

<!-- Focus-visible for accessibility -->
<input class="input focus:outline-none focus:ring-2 focus:ring-primary">
```

## Overflow

### Overflow
```html
overflow-auto overflow-hidden overflow-visible overflow-scroll
overflow-x-auto overflow-y-auto
overflow-x-hidden overflow-y-hidden
```

## Visibility

### Display
```html
hidden visible
```

### Screen Reader Only
```html
sr-only not-sr-only
```

## Common Utility Combinations

### Centered Container
```html
<div class="container mx-auto px-4">
```

### Flex Center
```html
<div class="flex items-center justify-center">
```

### Card Hover Effect
```html
<div class="transition-all duration-300 hover:shadow-2xl hover:-translate-y-1">
```

### Responsive Grid Layout
```html
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
```

### Full Height Section
```html
<div class="min-h-screen flex items-center justify-center">
```

### Sticky Header
```html
<nav class="sticky top-0 z-50 bg-base-100 shadow-lg">
```

### Truncated Text
```html
<p class="truncate max-w-xs">Long text that will be truncated...</p>
```

### Aspect Ratio Box
```html
<div class="aspect-square">
<div class="aspect-video">
```

## Dark Mode (if enabled)

### Dark Mode Classes
```html
<!-- Apply only in dark mode -->
dark:bg-gray-900 dark:text-white

<!-- Example -->
<div class="bg-white dark:bg-gray-900 text-black dark:text-white">
```

Note: DaisyUI handles theming differently via `data-theme` attribute, making dark mode classes less commonly needed.
